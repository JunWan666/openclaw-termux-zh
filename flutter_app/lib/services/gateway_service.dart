import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../constants.dart';
import '../models/gateway_state.dart';
import 'gateway_auth_config_service.dart';
import 'native_bridge.dart';
import 'preferences_service.dart';
import 'dashboard_url_resolver.dart';
import 'message_platform_config_service.dart';
import 'provider_config_service.dart';

class GatewayService {
  Timer? _healthTimer;
  Timer? _initialDelayTimer;
  StreamSubscription? _logSubscription;
  final _stateController = StreamController<GatewayState>.broadcast();
  GatewayState _state = const GatewayState();
  DateTime? _startingAt;
  bool _startInProgress = false;
  bool _dashboardUrlProbeInFlight = false;
  DateTime? _lastDashboardUrlProbeAt;
  bool _stateSyncInFlight = false;
  static final _leadingTimestamp = RegExp(r'^(\d{4}-\d{2}-\d{2}T\S+)\s+(.*)$');
  static final _boxDrawing = RegExp('[\\u2500-\\u257F\\u25C6\\u25C7]+');

  /// Strip terminal-only noise while preserving whitespace boundaries so
  /// adjacent log labels do not get glued onto `#token=...` URLs.
  static String _cleanForUrl(String text) {
    return text
        .replaceAll(AppConstants.ansiEscape, '')
        .replaceAll(_boxDrawing, '');
  }

  static String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute:$second';
  }

  static String? _normalizeLogLine(String line) {
    final clean = line.replaceAll(AppConstants.ansiEscape, '').trim();
    if (clean.isEmpty) return clean;

    var timestampMatch = _leadingTimestamp.firstMatch(clean);
    if (timestampMatch == null) {
      final fallbackTimestamp = _formatTimestamp(DateTime.now());
      return _rewriteCompatibilityLog(clean, fallbackTimestamp) ?? clean;
    }

    var timestamp = timestampMatch.group(1)!;
    var body = timestampMatch.group(2)!;

    final nestedMatch = _leadingTimestamp.firstMatch(body);
    if (nestedMatch != null) {
      timestamp = nestedMatch.group(1)!;
      body = nestedMatch.group(2)!;
    }

    final parsed = DateTime.tryParse(timestamp);
    final formattedTimestamp = parsed == null
        ? _formatTimestamp(DateTime.now())
        : _formatTimestamp(parsed);
    return _rewriteCompatibilityLog(body, formattedTimestamp) ??
        '$formattedTimestamp $body';
  }

  static String? _rewriteCompatibilityLog(String body, String timestamp) {
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty) {
      return null;
    }

    if (trimmedBody.contains(
      '[agents/model-providers] [xai-auth] bootstrap config fallback: no config-backed key found',
    )) {
      return null;
    }

    if (trimmedBody.contains(
      '[hooks/boot-md] boot-md skipped for agent startup run',
    )) {
      return null;
    }

    if (trimmedBody.contains(
      '[gateway] security warning: dangerous config flags enabled: gateway.controlUi.allowInsecureAuth=true',
    )) {
      return '$timestamp [INFO] Local Control UI compatibility mode is enabled for localhost access.';
    }

    if (trimmedBody.contains(
      '[bonjour] watchdog detected non-announced service; attempting re-advertise',
    )) {
      return '$timestamp [INFO] Bonjour service advertisement is retrying on Android.';
    }

    if (trimmedBody.contains(
      '[model-pricing] pricing bootstrap failed: TimeoutError: The operation was aborted due to timeout',
    )) {
      return '$timestamp [WARN] Model pricing bootstrap timed out; the gateway can continue running.';
    }

    return null;
  }

  static String _ts(String msg) => '${_formatTimestamp(DateTime.now())} $msg';

  Stream<GatewayState> get stateStream => _stateController.stream;
  GatewayState get state => _state;

  void _updateState(GatewayState newState) {
    _state = newState;
    _stateController.add(_state);
  }

  void clearLogs() {
    _updateState(_state.copyWith(logs: const []));
  }

  Future<String?> _readConfiguredDashboardUrl() async {
    return GatewayAuthConfigService.readDashboardUrl(
      baseUri: Uri.parse(AppConstants.gatewayUrl),
    );
  }

  /// Check if the gateway is already running (e.g. after app restart)
  /// and sync the UI state accordingly.  If not running but auto-start
  /// is enabled, start it automatically.
  Future<void> init() async {
    final prefs = PreferencesService();
    await prefs.init();
    final savedUrl = prefs.dashboardUrl;
    final configuredDashboardUrl = await _readConfiguredDashboardUrl();
    final initialDashboardUrl = configuredDashboardUrl ?? savedUrl;

    if (configuredDashboardUrl != null && configuredDashboardUrl != savedUrl) {
      await _persistDashboardUrl(configuredDashboardUrl);
    }

    // Always ensure directories and resolv.conf exist on app open.
    // Android may clear the files directory during an app update (#40).
    try {
      await NativeBridge.setupDirs();
    } catch (_) {}
    try {
      await NativeBridge.writeResolv();
    } catch (_) {}
    // Dart dart:io fallback if native calls failed (#40).
    try {
      final filesDir = await NativeBridge.getFilesDir();
      const resolvContent = 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n';
      final resolvFile = File('$filesDir/config/resolv.conf');
      if (!resolvFile.existsSync()) {
        Directory('$filesDir/config').createSync(recursive: true);
        resolvFile.writeAsStringSync(resolvContent);
      }
      // Also write into rootfs /etc/ so DNS works even if bind-mount fails
      final rootfsResolv = File('$filesDir/rootfs/ubuntu/etc/resolv.conf');
      if (!rootfsResolv.existsSync()) {
        rootfsResolv.parent.createSync(recursive: true);
        rootfsResolv.writeAsStringSync(resolvContent);
      }
    } catch (_) {}

    final alreadyRunning = await NativeBridge.isGatewayRunning();
    if (alreadyRunning) {
      // Write allowCommands config so the next gateway restart picks it up,
      // and in case the running gateway supports config hot-reload.
      await _writeNodeAllowConfig();
      _startingAt = DateTime.now();
      _updateState(_state.copyWith(
        status: GatewayStatus.starting,
        dashboardUrl: initialDashboardUrl,
        logs: [
          ..._state.logs,
          _ts('[INFO] Gateway process detected, reconnecting...')
        ],
      ));

      _subscribeLogs();
      _startHealthCheck();
      if (!DashboardUrlResolver.hasToken(initialDashboardUrl)) {
        unawaited(_maybeRefreshDashboardUrl(force: true));
      }
    } else if (prefs.autoStartGateway) {
      _updateState(_state.copyWith(
        logs: [..._state.logs, _ts('[INFO] Auto-starting gateway...')],
      ));
      await start();
    }
  }

  Future<void> syncStateFromSystem() async {
    if (_stateSyncInFlight) {
      return;
    }

    _stateSyncInFlight = true;
    try {
      final prefs = PreferencesService();
      await prefs.init();
      final configuredDashboardUrl = await _readConfiguredDashboardUrl();
      final persistedDashboardUrl = DashboardUrlResolver.normalizeDashboardUrl(
        prefs.dashboardUrl,
        baseUri: Uri.parse(AppConstants.gatewayUrl),
      );
      final currentDashboardUrl = DashboardUrlResolver.normalizeDashboardUrl(
        _state.dashboardUrl,
        baseUri: Uri.parse(AppConstants.gatewayUrl),
      );
      final dashboardUrl = configuredDashboardUrl ??
          currentDashboardUrl ??
          persistedDashboardUrl;
      if (configuredDashboardUrl != null &&
          configuredDashboardUrl != persistedDashboardUrl) {
        await _persistDashboardUrl(configuredDashboardUrl);
      }
      final isRunning = await NativeBridge.isGatewayRunning();

      if (_state.status == GatewayStatus.stopping && isRunning) {
        return;
      }

      if (isRunning) {
        _startingAt ??= DateTime.now();
        _subscribeLogs();
        _ensureHealthCheck();

        final healthy = await checkHealth();
        _updateState(_state.copyWith(
          status: healthy ? GatewayStatus.running : GatewayStatus.starting,
          clearError: true,
          startedAt: healthy ? (_state.startedAt ?? DateTime.now()) : null,
          dashboardUrl: dashboardUrl,
        ));

        await _refreshDashboardUrlFromConfig(notify: false);
        if (!DashboardUrlResolver.hasToken(dashboardUrl)) {
          unawaited(_maybeRefreshDashboardUrl(force: true));
        }
        return;
      }

      if (_state.status == GatewayStatus.stopped) {
        if (dashboardUrl != null && dashboardUrl != _state.dashboardUrl) {
          _updateState(_state.copyWith(dashboardUrl: dashboardUrl));
        }
        return;
      }

      _startingAt = null;
      _cancelAllTimers();
      await _logSubscription?.cancel();
      _logSubscription = null;
      _updateState(_state.copyWith(
        status: GatewayStatus.stopped,
        clearError: true,
        clearStartedAt: true,
        dashboardUrl: dashboardUrl,
      ));
    } finally {
      _stateSyncInFlight = false;
    }
  }

  void _subscribeLogs() {
    if (_logSubscription != null) {
      return;
    }
    _logSubscription = NativeBridge.gatewayLogStream.listen((log) {
      final normalizedLog = _normalizeLogLine(log);
      if (normalizedLog == null || normalizedLog.isEmpty) {
        return;
      }
      final logs = [..._state.logs, normalizedLog];
      if (logs.length > 500) {
        logs.removeRange(0, logs.length - 500);
      }
      final currentDashboardUrl = DashboardUrlResolver.normalizeDashboardUrl(
        _state.dashboardUrl,
        baseUri: Uri.parse(AppConstants.gatewayUrl),
      );
      String? dashboardUrl;
      final cleanLog = _cleanForUrl(normalizedLog);
      final resolvedUrl = DashboardUrlResolver.extractDashboardUrlFromText(
        cleanLog,
        baseUri: Uri.parse(AppConstants.gatewayUrl),
      );
      if (resolvedUrl != null) {
        dashboardUrl = resolvedUrl;
        unawaited(
          _persistDashboardUrl(
            resolvedUrl,
            notify: resolvedUrl != currentDashboardUrl,
          ),
        );
      }
      _updateState(
        _state.copyWith(
          logs: logs,
          dashboardUrl: dashboardUrl ?? currentDashboardUrl,
        ),
      );
    });
  }

  Future<void> _persistDashboardUrl(
    String dashboardUrl, {
    bool notify = false,
  }) async {
    try {
      final normalizedUrl = DashboardUrlResolver.normalizeDashboardUrl(
        dashboardUrl,
        baseUri: Uri.parse(AppConstants.gatewayUrl),
      );
      if (normalizedUrl == null) {
        return;
      }
      final prefs = PreferencesService();
      await prefs.init();
      prefs.dashboardUrl = normalizedUrl;
      if (notify) {
        await NativeBridge.showUrlNotification(
          normalizedUrl,
          title: 'Dashboard Ready',
        );
      }
    } catch (_) {
      // Ignore dashboard URL persistence failures and keep the gateway running.
    }
  }

  Future<void> _maybeRefreshDashboardUrl({bool force = false}) async {
    if (_dashboardUrlProbeInFlight) {
      return;
    }

    if (!force && DashboardUrlResolver.hasToken(_state.dashboardUrl)) {
      return;
    }

    final now = DateTime.now();
    if (!force &&
        _lastDashboardUrlProbeAt != null &&
        now.difference(_lastDashboardUrlProbeAt!) <
            const Duration(seconds: 15)) {
      return;
    }

    _dashboardUrlProbeInFlight = true;
    _lastDashboardUrlProbeAt = now;
    try {
      final resolvedUrl = await _resolveDashboardUrlFromGateway();
      if (resolvedUrl == null || resolvedUrl == _state.dashboardUrl) {
        return;
      }
      await _persistDashboardUrl(resolvedUrl);
      _updateState(_state.copyWith(dashboardUrl: resolvedUrl));
    } finally {
      _dashboardUrlProbeInFlight = false;
    }
  }

  Future<String?> _refreshDashboardUrlFromConfig({bool notify = false}) async {
    final configuredDashboardUrl = await _readConfiguredDashboardUrl();
    if (configuredDashboardUrl == null || configuredDashboardUrl.isEmpty) {
      return null;
    }

    final normalizedCurrent = DashboardUrlResolver.normalizeDashboardUrl(
      _state.dashboardUrl,
      baseUri: Uri.parse(AppConstants.gatewayUrl),
    );
    if (configuredDashboardUrl != normalizedCurrent) {
      await _persistDashboardUrl(
        configuredDashboardUrl,
        notify: notify,
      );
      _updateState(_state.copyWith(dashboardUrl: configuredDashboardUrl));
    }
    return configuredDashboardUrl;
  }

  Future<void> _bootstrapDashboardUrlFromConfig({
    Duration timeout = const Duration(seconds: 20),
    Duration interval = const Duration(seconds: 1),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_state.status == GatewayStatus.stopped ||
          _state.status == GatewayStatus.stopping) {
        return;
      }

      final url = await _refreshDashboardUrlFromConfig(notify: false);
      if (DashboardUrlResolver.hasToken(url)) {
        return;
      }

      await Future<void>.delayed(interval);
    }
  }

  Future<String?> _resolveDashboardUrlFromGateway() async {
    final configuredDashboardUrl = await _readConfiguredDashboardUrl();
    if (configuredDashboardUrl != null) {
      return configuredDashboardUrl;
    }

    final prefs = PreferencesService();
    await prefs.init();

    final candidateUris = <Uri>{Uri.parse(AppConstants.gatewayUrl)};

    void addCandidate(String? value) {
      if (value == null || value.isEmpty) {
        return;
      }
      final uri = Uri.tryParse(value);
      if (uri == null) {
        return;
      }
      candidateUris.add(DashboardUrlResolver.dashboardBaseUri(uri));
    }

    addCandidate(_state.dashboardUrl);
    addCandidate(prefs.dashboardUrl);

    for (final uri in candidateUris) {
      final resolvedUrl = await _probeDashboardUrl(uri);
      if (resolvedUrl != null) {
        return resolvedUrl;
      }
    }

    return null;
  }

  Future<String?> _probeDashboardUrl(Uri baseUri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      var currentUri = DashboardUrlResolver.dashboardBaseUri(baseUri);

      for (var redirectCount = 0; redirectCount < 4; redirectCount++) {
        final request = await client.getUrl(currentUri);
        request.followRedirects = false;
        final response =
            await request.close().timeout(const Duration(seconds: 3));
        final location = response.headers.value(HttpHeaders.locationHeader);

        if (location != null) {
          final resolvedFromLocation =
              DashboardUrlResolver.extractDashboardUrlFromText(
            location,
            baseUri: currentUri,
          );
          if (resolvedFromLocation != null) {
            return resolvedFromLocation;
          }
        }

        final body = await utf8.decodeStream(response).timeout(
              const Duration(seconds: 3),
            );
        final resolvedFromBody =
            DashboardUrlResolver.extractDashboardUrlFromText(
          body,
          baseUri: currentUri,
        );
        if (resolvedFromBody != null) {
          return resolvedFromBody;
        }

        if (!response.isRedirect || location == null) {
          break;
        }

        currentUri = currentUri.resolve(location);
      }
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }

    return null;
  }

  /// Patch /root/.openclaw/openclaw.json to clear denyCommands and set
  /// allowCommands for all node capabilities. This is the config file the
  /// gateway actually reads (not a separate gateway.json).
  Future<void> _writeNodeAllowConfig() async {
    const allowCommands = [
      'camera.snap',
      'camera.clip',
      'camera.list',
      'canvas.navigate',
      'canvas.eval',
      'canvas.snapshot',
      'flash.on',
      'flash.off',
      'flash.toggle',
      'flash.status',
      'location.get',
      'screen.record',
      'sensor.read',
      'sensor.list',
      'haptic.vibrate',
      'serial.list',
      'serial.connect',
      'serial.disconnect',
      'serial.write',
      'serial.read',
    ];
    // Use a Node.js one-liner to safely merge into existing openclaw.json
    // without clobbering other settings (API keys, onboarding config, etc.)
    final allowJson = jsonEncode(allowCommands);
    final script = '''
const fs = require("fs");
const p = "/root/.openclaw/openclaw.json";
let c = {};
try { c = JSON.parse(fs.readFileSync(p, "utf8")); } catch {}
if (!c.gateway) c.gateway = {};
if (!c.gateway.nodes) c.gateway.nodes = {};
c.gateway.nodes.denyCommands = [];
c.gateway.nodes.allowCommands = $allowJson;
fs.writeFileSync(p, JSON.stringify(c, null, 2));
''';
    var prootOk = false;
    try {
      await NativeBridge.runInProot(
        'node -e ${_shellEscape(script)}',
        timeout: 15,
      );
      prootOk = true;
    } catch (_) {}

    // Direct file I/O fallback (#56): if proot/node isn't ready, write the
    // config directly on the Android filesystem so the gateway still picks
    // up allowCommands on next start.
    if (!prootOk) {
      try {
        final filesDir = await NativeBridge.getFilesDir();
        final configFile =
            File('$filesDir/rootfs/ubuntu/root/.openclaw/openclaw.json');
        Map<String, dynamic> config = {};
        if (configFile.existsSync()) {
          try {
            config = Map<String, dynamic>.from(
                jsonDecode(configFile.readAsStringSync()) as Map);
          } catch (_) {}
        }
        config.putIfAbsent('gateway', () => <String, dynamic>{});
        final gw = config['gateway'] as Map<String, dynamic>;
        gw.putIfAbsent('nodes', () => <String, dynamic>{});
        final nodes = gw['nodes'] as Map<String, dynamic>;
        nodes['denyCommands'] = <String>[];
        nodes['allowCommands'] = allowCommands;
        configFile.parent.createSync(recursive: true);
        configFile.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(config),
        );
      } catch (_) {}
    }
  }

  /// Escape a string for use as a single-quoted shell argument.
  static String _shellEscape(String s) {
    return "'${s.replaceAll("'", "'\\''")}'";
  }

  Future<void> start() async {
    // Prevent concurrent start() calls from racing
    if (_startInProgress || _state.status == GatewayStatus.stopping) {
      return;
    }
    _startInProgress = true;

    final prefs = PreferencesService();
    await prefs.init();
    final savedUrl = prefs.dashboardUrl;
    final configuredDashboardUrl = await _readConfiguredDashboardUrl();

    _updateState(_state.copyWith(
      status: GatewayStatus.starting,
      clearError: true,
      logs: [..._state.logs, _ts('[INFO] Starting gateway...')],
      dashboardUrl: configuredDashboardUrl ?? savedUrl,
    ));

    try {
      // Ensure directories exist - Android may have cleared them (#40).
      // Non-fatal: the GatewayService foreground service also creates them.
      try {
        await NativeBridge.setupDirs();
      } catch (_) {}
      try {
        await NativeBridge.writeResolv();
      } catch (_) {}
      // Dart dart:io fallback if native calls failed (#40).
      try {
        final filesDir = await NativeBridge.getFilesDir();
        const resolvContent = 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n';
        final resolvFile = File('$filesDir/config/resolv.conf');
        if (!resolvFile.existsSync()) {
          Directory('$filesDir/config').createSync(recursive: true);
          resolvFile.writeAsStringSync(resolvContent);
        }
        // Also write into rootfs /etc/ so DNS works even if bind-mount fails
        final rootfsResolv = File('$filesDir/rootfs/ubuntu/etc/resolv.conf');
        if (!rootfsResolv.existsSync()) {
          rootfsResolv.parent.createSync(recursive: true);
          rootfsResolv.writeAsStringSync(resolvContent);
        }
      } catch (_) {}
      await ProviderConfigService.migrateCustomProviderConfigIfNeeded();
      await ProviderConfigService.ensureGatewayDefaults();
      await MessagePlatformConfigService.migrateFeishuConfigIfNeeded();
      await _writeNodeAllowConfig();
      final refreshedDashboardUrl = await _readConfiguredDashboardUrl();
      if (refreshedDashboardUrl != null) {
        await _persistDashboardUrl(refreshedDashboardUrl);
        _updateState(_state.copyWith(dashboardUrl: refreshedDashboardUrl));
      }
      _startingAt = DateTime.now();
      _subscribeLogs();
      await NativeBridge.startGateway();
      _startHealthCheck();
      unawaited(_bootstrapDashboardUrlFromConfig());
    } catch (e) {
      _updateState(_state.copyWith(
        status: GatewayStatus.error,
        errorMessage: 'Failed to start: $e',
        logs: [..._state.logs, _ts('[ERROR] Failed to start: $e')],
      ));
    } finally {
      _startInProgress = false;
    }
  }

  Future<void> stop() async {
    _cancelAllTimers();
    _startingAt = null;

    if (_state.status == GatewayStatus.stopped ||
        _state.status == GatewayStatus.stopping) {
      return;
    }

    _updateState(_state.copyWith(
      status: GatewayStatus.stopping,
      clearError: true,
      clearStartedAt: true,
      logs: [..._state.logs, _ts('[INFO] Stopping gateway...')],
    ));

    try {
      await NativeBridge.stopGateway();
      await _logSubscription?.cancel();
      _logSubscription = null;
      _updateState(_state.copyWith(
        status: GatewayStatus.stopped,
        clearError: true,
        clearStartedAt: true,
        logs: [..._state.logs, _ts('[INFO] Gateway stopped')],
      ));
    } catch (e) {
      _updateState(_state.copyWith(
        status: GatewayStatus.error,
        errorMessage: 'Failed to stop: $e',
        logs: [..._state.logs, _ts('[ERROR] Failed to stop: $e')],
      ));
    }
  }

  /// Cancel both the initial delay timer and periodic health timer.
  void _cancelAllTimers() {
    _initialDelayTimer?.cancel();
    _initialDelayTimer = null;
    _healthTimer?.cancel();
    _healthTimer = null;
  }

  void _ensureHealthCheck() {
    if (_initialDelayTimer != null || _healthTimer != null) {
      return;
    }
    _startHealthCheck();
  }

  void _startHealthCheck() {
    _cancelAllTimers();
    // Start probing quickly so the homepage status and Web UI URL update sooner.
    _initialDelayTimer = Timer(const Duration(seconds: 3), () {
      _initialDelayTimer = null;
      if (_state.status == GatewayStatus.stopped ||
          _state.status == GatewayStatus.stopping) {
        return;
      }
      _checkHealth();
      _healthTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _checkHealth(),
      );
    });
  }

  Future<void> _checkHealth() async {
    try {
      final response = await http
          .head(Uri.parse(AppConstants.gatewayUrl))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode < 500 && _state.status != GatewayStatus.running) {
        _updateState(_state.copyWith(
          status: GatewayStatus.running,
          startedAt: _state.startedAt ?? DateTime.now(),
          logs: [..._state.logs, _ts('[INFO] Gateway is healthy')],
        ));
      }

      await _refreshDashboardUrlFromConfig(notify: false);
      if (response.statusCode < 500 &&
          !DashboardUrlResolver.hasToken(_state.dashboardUrl)) {
        unawaited(_maybeRefreshDashboardUrl());
      }
    } catch (_) {
      if (_state.status == GatewayStatus.stopping) {
        return;
      }
      // Still starting or temporarily unreachable
      final isRunning = await NativeBridge.isGatewayRunning();
      if (!isRunning && _state.status != GatewayStatus.stopped) {
        // Grace period: give the service time to boot before declaring failure.
        if (_startingAt != null &&
            _state.status == GatewayStatus.starting &&
            DateTime.now().difference(_startingAt!).inSeconds < 45) {
          _updateState(_state.copyWith(
            logs: [
              ..._state.logs,
              _ts('[INFO] Starting, waiting for gateway...')
            ],
          ));
          return;
        }
        _updateState(_state.copyWith(
          status: GatewayStatus.stopped,
          logs: [..._state.logs, _ts('[WARN] Gateway process not running')],
        ));
        _cancelAllTimers();
      }
    }
  }

  Future<bool> checkHealth() async {
    try {
      final response = await http
          .head(Uri.parse(AppConstants.gatewayUrl))
          .timeout(const Duration(seconds: 3));
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  Future<void> applyConfigChanges({String source = 'configuration'}) async {
    final isGatewayActive = _state.status == GatewayStatus.running ||
        _state.status == GatewayStatus.starting;

    if (!isGatewayActive) {
      _updateState(_state.copyWith(logs: [
        ..._state.logs,
        _ts('[INFO] $source updated. Changes will apply the next time the gateway starts.'),
      ]));
      return;
    }

    _updateState(_state.copyWith(logs: [
      ..._state.logs,
      _ts('[INFO] $source updated. OpenClaw will hot-reload the new configuration.'),
    ]));

    try {
      await ProviderConfigService.ensureGatewayDefaults();
      await _refreshDashboardUrlFromConfig(notify: false);
      unawaited(_maybeRefreshDashboardUrl(force: true));
      await syncStateFromSystem();
    } catch (e) {
      _updateState(_state.copyWith(logs: [
        ..._state.logs,
        _ts('[ERROR] Failed to refresh $source automatically: $e'),
      ]));
    }
  }

  void dispose() {
    _cancelAllTimers();
    _logSubscription?.cancel();
    _stateController.close();
  }
}
