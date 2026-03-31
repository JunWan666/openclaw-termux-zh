import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'native_bridge.dart';

class CpolarModuleInfo {
  final String version;
  final int webPort;
  final String architecture;
  final String downloadUrl;
  final String installedAt;

  const CpolarModuleInfo({
    required this.version,
    required this.webPort,
    required this.architecture,
    required this.downloadUrl,
    required this.installedAt,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'webPort': webPort,
        'architecture': architecture,
        'downloadUrl': downloadUrl,
        'installedAt': installedAt,
      };

  factory CpolarModuleInfo.fromJson(Map<String, dynamic> json) {
    return CpolarModuleInfo(
      version: json['version']?.toString().trim() ?? '',
      webPort: (json['webPort'] as num?)?.toInt() ??
          CpolarPackageService.defaultPort,
      architecture: json['architecture']?.toString().trim() ?? '',
      downloadUrl: json['downloadUrl']?.toString().trim() ?? '',
      installedAt: json['installedAt']?.toString().trim() ?? '',
    );
  }
}

class CpolarPackageState {
  final bool installed;
  final bool running;
  final bool dashboardReachable;
  final bool archSupported;
  final bool authtokenConfigured;
  final String architecture;
  final String? installedVersion;
  final String? authtokenPreview;
  final int dashboardPort;
  final String configPath;
  final String logPath;
  final String binaryPath;
  final String cachePath;
  final String downloadUrl;
  final String tokenPageUrl;
  final List<String> tunnelNames;
  final List<String> deviceIps;
  final List<String> recentLogs;

  const CpolarPackageState({
    required this.installed,
    required this.running,
    required this.dashboardReachable,
    required this.archSupported,
    required this.authtokenConfigured,
    required this.architecture,
    required this.dashboardPort,
    required this.configPath,
    required this.logPath,
    required this.binaryPath,
    required this.cachePath,
    required this.downloadUrl,
    required this.tokenPageUrl,
    required this.tunnelNames,
    required this.deviceIps,
    required this.recentLogs,
    this.installedVersion,
    this.authtokenPreview,
  });

  const CpolarPackageState.empty()
      : installed = false,
        running = false,
        dashboardReachable = false,
        archSupported = false,
        authtokenConfigured = false,
        architecture = '',
        installedVersion = null,
        authtokenPreview = null,
        dashboardPort = CpolarPackageService.defaultPort,
        configPath = CpolarPackageService._configGuestPath,
        logPath = CpolarPackageService._logGuestPath,
        binaryPath = CpolarPackageService._binaryGuestPath,
        cachePath = CpolarPackageService._packageGuestDir,
        downloadUrl = '',
        tokenPageUrl = CpolarPackageService.tokenPageUrl,
        tunnelNames = const <String>[],
        deviceIps = const <String>[],
        recentLogs = const <String>[];

  String get dashboardUrl => 'http://127.0.0.1:$dashboardPort';

  bool get canOpenDashboard => installed && dashboardReachable;
}

class CpolarPackageService {
  static const defaultPort = 9200;
  static const tokenPageUrl = 'https://dashboard.cpolar.com/auth';
  static const runtimeHome = '/root/.openclaw';
  static const _cpolarVersion = '3.3.12';
  static const _demoConfigUrl =
      'http://www.cpolar.com/static/downloads/cpolar.demo.yml';
  static const _generatedConfigMarker = 'OpenClaw generated cpolar config.';
  static const _legacyGeneratedConfigMarker =
      'All In Ubuntu generated cpolar config.';

  static const _moduleGuestDir = '$runtimeHome/modules/cpolar';
  static const _moduleRootfsDir = 'root/.openclaw/modules/cpolar';
  static const _legacyConfigRootfsPath = '$_moduleRootfsDir/config/cpolar.yml';
  static const _configGuestPath = '/usr/local/etc/cpolar/cpolar.yml';
  static const _configRootfsPath = 'usr/local/etc/cpolar/cpolar.yml';
  static const _logGuestPath = '/var/log/cpolar/access.log';
  static const _logRootfsPath = 'var/log/cpolar/access.log';
  static const _binaryGuestPath = '/usr/local/bin/cpolar';
  static const _packageGuestDir = '$_moduleGuestDir/cache';
  static const _moduleInfoRootfsPath = '$_moduleRootfsDir/module.json';
  static const _bashrcRootfsPath = 'root/.bashrc';
  static const _bashrcStartMarker = '# >>> openclaw cpolar autostart >>>';
  static const _bashrcEndMarker = '# <<< openclaw cpolar autostart <<<';

  static String get configGuestPath => _configGuestPath;
  static String get logGuestPath => _logGuestPath;
  static String get binaryGuestPath => _binaryGuestPath;
  static String get packageGuestDir => _packageGuestDir;

  static Future<CpolarPackageState> readState() async {
    final arch = await NativeBridge.getArch();
    final downloadUrl = _downloadUrlForArch(arch);
    final moduleInfo = await _readModuleInfo();
    final installed = await _isInstalled();
    final serviceRunning = await _isServiceRunning();
    final processRunning = installed ? await _hasRunningProcess() : false;
    final configContent = await _readConfigContent();
    final port =
        _parseWebPort(configContent) ?? moduleInfo?.webPort ?? defaultPort;
    final authtoken = _parseAuthtoken(configContent);
    final dashboardReachable =
        installed ? await _isDashboardReachable(port) : false;
    final portOpen = installed ? await _isTcpPortOpen(port) : false;
    final logs = installed ? await _readRecentLogs() : const <String>[];
    final deviceIps = installed ? await _readDeviceIps() : const <String>[];

    return CpolarPackageState(
      installed: installed,
      running:
          serviceRunning || processRunning || dashboardReachable || portOpen,
      dashboardReachable: dashboardReachable,
      archSupported: downloadUrl != null,
      authtokenConfigured: authtoken != null && authtoken.isNotEmpty,
      architecture: arch,
      installedVersion:
          moduleInfo?.version.isNotEmpty == true ? moduleInfo!.version : null,
      authtokenPreview: _maskAuthtoken(authtoken),
      dashboardPort: port,
      configPath: _configGuestPath,
      logPath: _logGuestPath,
      binaryPath: _binaryGuestPath,
      cachePath: _packageGuestDir,
      downloadUrl: downloadUrl ?? '',
      tokenPageUrl: tokenPageUrl,
      tunnelNames: _parseTunnelNames(configContent),
      deviceIps: deviceIps,
      recentLogs: logs,
    );
  }

  static Future<void> installOrUpdateLatest({
    void Function(List<String> lines)? onLogChanged,
  }) async {
    await _ensureRuntimeReady();

    final arch = await NativeBridge.getArch();
    final downloadUrl = _downloadUrlForArch(arch);
    if (downloadUrl == null) {
      throw Exception(
          'Current device architecture is not supported by cpolar: $arch');
    }

    final existingInfo = await _readModuleInfo();
    final configContent = await _readConfigContent();
    final port =
        _parseWebPort(configContent) ?? existingInfo?.webPort ?? defaultPort;

    if (await _isServiceRunning() ||
        await _hasRunningProcess() ||
        await _isEndpointActive(port)) {
      await stop();
    } else {
      await _removeAutostartBashrcBlock();
      await _terminateResidualProcesses();
    }

    final output = await _runInstallCommandWithLogs(
      downloadUrl,
      onLogChanged: onLogChanged,
    );

    final version =
        _parseInstalledVersion(output) ?? existingInfo?.version ?? 'stable';
    final moduleInfo = CpolarModuleInfo(
      version: version,
      webPort: port,
      architecture: arch,
      downloadUrl: downloadUrl,
      installedAt: existingInfo?.installedAt.isNotEmpty == true
          ? existingInfo!.installedAt
          : DateTime.now().toUtc().toIso8601String(),
    );

    await NativeBridge.writeRootfsFile(
      _moduleInfoRootfsPath,
      const JsonEncoder.withIndent('  ').convert(moduleInfo.toJson()),
    );

    await start(moduleInfo.webPort);
  }

  static Future<void> start([int? port]) async {
    await _ensureRuntimeReady();

    final moduleInfo = await _readModuleInfo();
    final preferredPort = port ?? moduleInfo?.webPort ?? defaultPort;
    await _ensureUsableConfig(preferredPort);
    final configContent = await _readConfigContent();
    final resolvedPort = _parseWebPort(configContent) ?? preferredPort;

    if (!await _isInstalled()) {
      throw Exception('cpolar is not installed.');
    }

    await _writeAutostartBashrcBlock();
    await _terminateResidualProcesses();

    await NativeBridge.startCpolarService(
      binaryPath: _binaryGuestPath,
      configPath: _configGuestPath,
      logPath: _logGuestPath,
      webPort: resolvedPort,
    );

    await _waitForStarted(resolvedPort);
  }

  static Future<void> stop() async {
    final configContent = await _readConfigContent();
    final moduleInfo = await _readModuleInfo();
    final port =
        _parseWebPort(configContent) ?? moduleInfo?.webPort ?? defaultPort;

    await _removeAutostartBashrcBlock();
    try {
      await NativeBridge.stopCpolarService();
    } finally {
      await _terminateResidualProcesses();
    }

    await _waitForStopped(port);
  }

  static Future<void> uninstall() async {
    final configContent = await _readConfigContent();
    final moduleInfo = await _readModuleInfo();
    final port =
        _parseWebPort(configContent) ?? moduleInfo?.webPort ?? defaultPort;

    await _removeAutostartBashrcBlock();

    if (await _isServiceRunning() ||
        await _hasRunningProcess() ||
        await _isEndpointActive(port)) {
      try {
        await NativeBridge.stopCpolarService();
      } finally {
        await _terminateResidualProcesses();
      }
    } else {
      await _terminateResidualProcesses();
    }

    await NativeBridge.runInProot(
      '''
rm -f ${_shellQuote('/usr/local/bin/cpolar')}
rm -f ${_shellQuote('/usr/bin/cpolar')}
rm -f ${_shellQuote('/etc/systemd/system/cpolar.service')}
rm -f ${_shellQuote('/etc/systemd/system/cpolar@.service')}
rm -rf ${_shellQuote('/etc/systemd/system/cpolar.service.d')}
rm -rf ${_shellQuote('/etc/systemd/system/cpolar@.service.d')}
rm -rf ${_shellQuote('/usr/local/etc/cpolar')}
rm -rf ${_shellQuote('/var/log/cpolar')}
rm -rf ${_shellQuote(_moduleGuestDir)}
''',
      timeout: 300,
    );
  }

  static Future<void> ensureConfigFile() async {
    final moduleInfo = await _readModuleInfo();
    await _ensureUsableConfig(moduleInfo?.webPort ?? defaultPort);
  }

  static Future<void> writeAuthtoken(String token) async {
    final trimmed = token.trim();
    final moduleInfo = await _readModuleInfo();
    await _ensureUsableConfig(moduleInfo?.webPort ?? defaultPort);

    final existing = await _readConfigContent();
    final current = existing.isNotEmpty
        ? existing
        : _buildDefaultConfig(moduleInfo?.webPort ?? defaultPort);
    final updated = _upsertAuthtoken(current, trimmed.isEmpty ? null : trimmed);
    await NativeBridge.writeRootfsFile(
      _configRootfsPath,
      _ensureTrailingNewline(updated),
    );
  }

  static Future<String?> readAuthtoken() async {
    final content = await _readConfigContent();
    return _parseAuthtoken(content);
  }

  static Future<List<String>> readRecentLogs() async {
    return _readRecentLogs();
  }

  static Future<bool> _isInstalled() async {
    try {
      final output = await NativeBridge.runInProot(
        'if [ -x ${_shellQuote(_binaryGuestPath)} ]; then echo installed; fi',
        timeout: 15,
      );
      return output.trim().contains('installed');
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _isServiceRunning() async {
    try {
      return await NativeBridge.isCpolarServiceRunning();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _hasRunningProcess() async {
    try {
      final output = await NativeBridge.runInProot(
        r'''
found=0
for proc_dir in /proc/[0-9]*; do
  [ -r "$proc_dir/comm" ] || continue
  if [ "$(cat "$proc_dir/comm" 2>/dev/null || true)" = "cpolar" ]; then
    found=1
    break
  fi
done
if [ "$found" -eq 1 ]; then
  echo running
fi
''',
        timeout: 15,
      );
      return output.trim().contains('running');
    } catch (_) {
      return false;
    }
  }

  static Future<String> _readConfigContent() async {
    final current = await NativeBridge.readRootfsFile(_configRootfsPath);
    if (current != null && current.trim().isNotEmpty) {
      return current;
    }
    final legacy = await NativeBridge.readRootfsFile(_legacyConfigRootfsPath);
    return legacy ?? '';
  }

  static Future<String> _readBashrcContent() async {
    return await NativeBridge.readRootfsFile(_bashrcRootfsPath) ?? '';
  }

  static Future<void> _ensureRuntimeReady() async {
    try {
      await NativeBridge.setupDirs();
    } catch (_) {}
    try {
      await NativeBridge.writeResolv();
    } catch (_) {}
  }

  static Future<void> _ensureUsableConfig(int port) async {
    final current = await _readConfigContent();
    final normalized = _normalizeConfig(current, port);
    if (current.isNotEmpty &&
        _normalizeLineEndings(current).trimRight() ==
            _normalizeLineEndings(normalized).trimRight()) {
      return;
    }
    await NativeBridge.writeRootfsFile(_configRootfsPath, normalized);
  }

  static Future<void> _writeAutostartBashrcBlock() async {
    final current = _normalizeLineEndings(await _readBashrcContent());
    final withoutManagedBlock = _stripManagedBashrcBlock(current);
    final remainder = withoutManagedBlock.replaceFirst(RegExp(r'^\n+'), '');
    final block = _buildAutostartBashrcBlock().trimRight();
    final updated = remainder.isEmpty ? block : '$block\n\n$remainder';

    await NativeBridge.writeRootfsFile(
      _bashrcRootfsPath,
      _ensureTrailingNewline(updated),
    );
  }

  static Future<void> _removeAutostartBashrcBlock() async {
    final current = _normalizeLineEndings(await _readBashrcContent());
    if (current.isEmpty) {
      return;
    }

    final cleaned = _stripManagedBashrcBlock(current);
    if (cleaned.trimRight() == current.trimRight()) {
      return;
    }

    await NativeBridge.writeRootfsFile(_bashrcRootfsPath, cleaned);
  }

  static String _stripManagedBashrcBlock(String content) {
    final pattern = RegExp(
      '${RegExp.escape(_bashrcStartMarker)}[\\s\\S]*?${RegExp.escape(_bashrcEndMarker)}\\n*',
    );
    final stripped = content.replaceFirst(pattern, '');
    return _ensureTrailingNewline(
      stripped.replaceFirst(RegExp(r'^\n+'), '').trimRight(),
    );
  }

  static String _buildAutostartBashrcBlock() {
    return '''
$_bashrcStartMarker
cpolar_autostart_running=0
for proc_dir in /proc/[0-9]*; do
  [ -r "\$proc_dir/comm" ] || continue
  if [ "\$(cat "\$proc_dir/comm" 2>/dev/null || true)" = "cpolar" ]; then
    cpolar_autostart_running=1
    break
  fi
done
if [ "\$cpolar_autostart_running" -ne 1 ] && [ -x ${_shellQuote(_binaryGuestPath)} ]; then
  mkdir -p ${_shellQuote('/usr/local/etc/cpolar')} ${_shellQuote('/var/log/cpolar')}
  touch ${_shellQuote(_logGuestPath)}
  nohup ${_shellQuote(_binaryGuestPath)} start-all -daemon=on -dashboard=on -config=${_shellQuote(_configGuestPath)} -log=${_shellQuote(_logGuestPath)} > /dev/null 2>&1 &
fi
unset cpolar_autostart_running
$_bashrcEndMarker
''';
  }

  static Future<CpolarModuleInfo?> _readModuleInfo() async {
    try {
      final content = await NativeBridge.readRootfsFile(_moduleInfoRootfsPath);
      if (content == null || content.trim().isEmpty) {
        return null;
      }
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return CpolarModuleInfo.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>> _readRecentLogs() async {
    try {
      final output = await NativeBridge.runInProot(
        'if [ -f ${_shellQuote(_logGuestPath)} ]; then '
        'tail -n 120 ${_shellQuote(_logGuestPath)}; '
        'fi',
        timeout: 20,
      );
      return const LineSplitter()
          .convert(output)
          .map((line) => line.trimRight())
          .where((line) => line.isNotEmpty)
          .toList();
    } catch (_) {
      return const <String>[];
    }
  }

  static Future<String> _runInstallCommandWithLogs(
    String downloadUrl, {
    void Function(List<String> lines)? onLogChanged,
  }) async {
    final installFuture = NativeBridge.runInProot(
      _buildInstallCommand(downloadUrl),
      timeout: 1800,
    );

    var emittedLines = const <String>[];
    while (true) {
      emittedLines = await _emitInstallLogUpdate(
        onLogChanged: onLogChanged,
        previousLines: emittedLines,
      );

      final completed = await Future.any<bool>([
        installFuture.then((_) => true, onError: (_) => true),
        Future<bool>.delayed(
          const Duration(milliseconds: 700),
          () => false,
        ),
      ]);
      if (completed) {
        break;
      }
    }

    await _emitInstallLogUpdate(
      onLogChanged: onLogChanged,
      previousLines: emittedLines,
      force: true,
    );

    return installFuture;
  }

  static Future<List<String>> _emitInstallLogUpdate({
    required void Function(List<String> lines)? onLogChanged,
    required List<String> previousLines,
    bool force = false,
  }) async {
    if (onLogChanged == null) {
      return previousLines;
    }

    final currentLines = await _readInstallLogLines();
    if (force || !_sameLogLines(previousLines, currentLines)) {
      onLogChanged(currentLines);
      return currentLines;
    }
    return previousLines;
  }

  static Future<List<String>> _readInstallLogLines() async {
    try {
      final content = await NativeBridge.readRootfsFile(_logRootfsPath);
      if (content == null || content.trim().isEmpty) {
        return const <String>[];
      }

      final lines = const LineSplitter()
          .convert(content)
          .map((line) => line.trimRight())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);

      if (lines.length <= 140) {
        return lines;
      }
      return lines.sublist(lines.length - 140);
    } catch (_) {
      return const <String>[];
    }
  }

  static bool _sameLogLines(List<String> left, List<String> right) {
    if (identical(left, right)) {
      return true;
    }
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  static Future<List<String>> _readDeviceIps() async {
    try {
      final ips = await NativeBridge.getDeviceIps();
      return ips.where((ip) => ip.trim().isNotEmpty).toList();
    } catch (_) {
      return const <String>[];
    }
  }

  static Future<bool> _isDashboardReachable(int port) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/'));
      request.followRedirects = false;
      final response =
          await request.close().timeout(const Duration(seconds: 4));
      await response.drain<void>();
      return response.statusCode >= 200 && response.statusCode < 500;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static Future<bool> _isTcpPortOpen(int port) async {
    try {
      final socket = await Socket.connect(
        '127.0.0.1',
        port,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _isEndpointActive(int port) async {
    if (await _isDashboardReachable(port)) {
      return true;
    }
    return _isTcpPortOpen(port);
  }

  static Future<void> _waitForStarted(int port) async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      if (await _hasRunningProcess() || await _isEndpointActive(port)) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 900));
    }

    final logs = await _readRecentLogs();
    final tail =
        logs.skip(logs.length > 20 ? logs.length - 20 : 0).join(' | ').trim();
    final suffix = tail.isEmpty ? '' : ' Recent logs: $tail';
    throw Exception(
        'cpolar did not expose a process or dashboard on port $port.$suffix');
  }

  static Future<void> _waitForStopped(int port) async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(deadline)) {
      if (!await _hasRunningProcess() && !await _isEndpointActive(port)) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    throw Exception('cpolar is still running or still occupies port $port.');
  }

  static Future<void> _terminateResidualProcesses() async {
    try {
      await NativeBridge.runInProot(
        r'''
current_pid="$$"
parent_pid="$PPID"

collect_cpolar_pids() {
  for proc_dir in /proc/[0-9]*; do
    pid="${proc_dir##*/}"
    [ "$pid" = "$current_pid" ] && continue
    [ "$pid" = "$parent_pid" ] && continue
    [ -r "$proc_dir/comm" ] || continue
    if [ "$(cat "$proc_dir/comm" 2>/dev/null || true)" = "cpolar" ]; then
      echo "$pid"
    fi
  done
}

pids="$(collect_cpolar_pids)"
if [ -n "$pids" ]; then
  for pid in $pids; do
    kill "$pid" 2>/dev/null || true
  done
  sleep 1
  for pid in $pids; do
    kill -9 "$pid" 2>/dev/null || true
  done
fi
''',
        timeout: 20,
      );
    } catch (_) {}
  }

  static String _buildInstallCommand(String downloadUrl) {
    return '''
set -eu
log_file=${_shellQuote(_logGuestPath)}
download_url=${_shellQuote(downloadUrl)}
demo_config_url=${_shellQuote(_demoConfigUrl)}
binary_target=${_shellQuote(_binaryGuestPath)}
config_target=${_shellQuote(_configGuestPath)}
cache_dir=${_shellQuote(_packageGuestDir)}
archive_path="\$cache_dir/cpolar.zip"
extract_dir="\$cache_dir/extract"
demo_config_path="\$cache_dir/cpolar.demo.yml"

mkdir -p ${_shellQuote('/usr/local/etc/cpolar')} ${_shellQuote('/var/log/cpolar')} ${_shellQuote(_packageGuestDir)} /usr/local/bin /usr/bin
: > "\$log_file"

emit_failure_tail() {
  local status="\$1"
  {
    echo "cpolar installation failed (exit code \$status)"
    if [ -f "\$log_file" ]; then
      echo '---- cpolar install log tail ----'
      tail -n 80 "\$log_file" || true
      echo '---- end of log ----'
    fi
  } >&2
}

trap 'status=\$?; trap - EXIT; if [ "\$status" -ne 0 ]; then emit_failure_tail "\$status"; fi; exit "\$status"' EXIT

log() {
  printf '[%s] %s\\n' "\$(date -Iseconds 2>/dev/null || date)" "\$1" >> "\$log_file"
}

ensure_archive_tools() {
  if command -v unzip >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
    return 0
  fi

  log "missing curl/unzip, installing required dependencies"
  dpkg --configure -a >> "\$log_file" 2>&1 || true
  apt-get -f install -y >> "\$log_file" 2>&1 || true
  apt-get update >> "\$log_file" 2>&1
  DEBIAN_FRONTEND=noninteractive apt-get install -y unzip ca-certificates curl >> "\$log_file" 2>&1
}

direct_install() {
  log "starting direct cpolar binary install"
  ensure_archive_tools
  rm -rf "\$extract_dir"
  mkdir -p "\$extract_dir"
  curl --fail --location --retry 3 --connect-timeout 20 "\$download_url" -o "\$archive_path" >> "\$log_file" 2>&1
  unzip -oq "\$archive_path" -d "\$extract_dir" >> "\$log_file" 2>&1

  if [ ! -f "\$extract_dir/cpolar" ]; then
    echo "cpolar archive extracted, but binary was not found." >&2
    exit 1
  fi

  cp "\$extract_dir/cpolar" "\$binary_target"
  chmod 755 "\$binary_target"
  ln -sf "\$binary_target" ${_shellQuote('/usr/bin/cpolar')}
  log "binary installed to /usr/local/bin/cpolar and linked to /usr/bin/cpolar"

  if [ ! -s "\$config_target" ] || grep -q 'OpenClaw generated cpolar config\\.' "\$config_target" || grep -q 'All In Ubuntu generated cpolar config\\.' "\$config_target"; then
    if curl --fail --location --retry 3 --connect-timeout 20 "\$demo_config_url" -o "\$demo_config_path" >> "\$log_file" 2>&1; then
      cp "\$demo_config_path" "\$config_target"
      log "demo config installed to /usr/local/etc/cpolar/cpolar.yml"
    else
      log "demo config download failed, app fallback config will be used on first start"
    fi
  else
    log "keeping existing cpolar config"
  fi
}

direct_install

if [ ! -x "\$binary_target" ]; then
  echo "direct cpolar installation finished without /usr/local/bin/cpolar" >&2
  exit 1
fi

mkdir -p ${_shellQuote('/usr/local/etc/cpolar')} ${_shellQuote('/var/log/cpolar')}
ln -sf "\$binary_target" ${_shellQuote('/usr/bin/cpolar')}

version_line="\$("\$binary_target" version 2>>"\$log_file" | head -n 1 || true)"
version_value="\$(printf '%s' "\$version_line" | awk 'NR==1 {print \$3}')"
if [ -z "\$version_value" ]; then
  version_value="stable"
fi
printf 'installed %s\\n' "\$version_value"
''';
  }

  static String _buildDefaultConfig(int port) {
    return '''
# $_generatedConfigMarker
# Open http://127.0.0.1:$port after startup to complete the web login.
${_buildSampleTunnelsBlock()}
''';
  }

  static String _buildSampleTunnelsBlock() {
    return '''
tunnels:
  website:
    addr: 8080
    proto: http
  ssh:
    addr: 22
    proto: tcp
''';
  }

  static int? _parseWebPort(String? configContent) {
    if (configContent == null || configContent.trim().isEmpty) {
      return null;
    }
    return _parsePortValue(
          _readConfigValue(configContent, 'client_dashboard_addr'),
        ) ??
        _parsePortValue(_readConfigValue(configContent, 'web_addr'));
  }

  static String? _parseAuthtoken(String? configContent) {
    if (configContent == null || configContent.trim().isEmpty) {
      return null;
    }
    final match = RegExp(
      r'^[ \t]*authtoken:\s*(.+?)\s*$',
      multiLine: true,
    ).firstMatch(configContent);
    final token = match?.group(1)?.trim();
    if (token == null || token.isEmpty) {
      return null;
    }
    return _unquoteYamlScalar(token);
  }

  static List<String> _parseTunnelNames(String? configContent) {
    if (configContent == null || configContent.trim().isEmpty) {
      return const <String>[];
    }

    final names = <String>[];
    var inTunnels = false;
    for (final rawLine in const LineSplitter().convert(configContent)) {
      final trimmed = rawLine.trim();

      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }

      if (!inTunnels) {
        if (trimmed == 'tunnels:' || trimmed.startsWith('tunnels: ')) {
          if (trimmed.contains('{}')) {
            return const <String>[];
          }
          inTunnels = true;
        }
        continue;
      }

      if (!rawLine.startsWith('  ')) {
        break;
      }

      final match =
          RegExp(r'^\s{2,}([A-Za-z0-9._-]+):\s*$').firstMatch(rawLine);
      if (match != null) {
        names.add(match.group(1)!);
      }
    }

    return names;
  }

  static String? _maskAuthtoken(String? token) {
    if (token == null || token.isEmpty) {
      return null;
    }
    if (token.length <= 8) {
      return token;
    }
    return '${token.substring(0, 4)}...${token.substring(token.length - 4)}';
  }

  static String _upsertAuthtoken(String content, String? token) {
    final pattern = RegExp(r'^[ \t]*authtoken:\s*.+?\s*$\n?', multiLine: true);

    if (token == null || token.isEmpty) {
      final cleaned = content.replaceAll(pattern, '');
      return cleaned.replaceFirst(RegExp(r'^\n+'), '');
    }

    final quoted = _yamlSingleQuoted(token);
    final line = 'authtoken: $quoted';
    if (pattern.hasMatch(content)) {
      return content.replaceFirst(pattern, '$line\n');
    }
    return '$line\n${content.trimLeft()}';
  }

  static String? _parseInstalledVersion(String output) {
    final matches =
        RegExp(r'installed\s+(\S+)').allMatches(output).toList(growable: false);
    if (matches.isEmpty) {
      return null;
    }
    return matches.last.group(1)?.trim();
  }

  static String _ensureTrailingNewline(String value) {
    if (value.isEmpty || value.endsWith('\n')) {
      return value;
    }
    return '$value\n';
  }

  static String _normalizeConfig(String? content, int fallbackPort) {
    final source = _normalizeLineEndings(content ?? '').trim();
    final authtoken = _parseAuthtoken(source);

    if (source.isEmpty ||
        source.contains(_generatedConfigMarker) ||
        source.contains(_legacyGeneratedConfigMarker) ||
        source.contains('tunnels: {}')) {
      return _withAuthtoken(_buildDefaultConfig(fallbackPort), authtoken);
    }

    var normalized = source;
    if (!_hasUsableTunnels(normalized)) {
      normalized = _upsertTunnelsBlock(normalized, _buildSampleTunnelsBlock());
    }

    return _ensureTrailingNewline(
      _withAuthtoken(normalized, authtoken).trimRight(),
    );
  }

  static bool _hasUsableTunnels(String content) {
    return _parseTunnelNames(content).isNotEmpty;
  }

  static String _upsertTunnelsBlock(String content, String replacement) {
    final lines = const LineSplitter().convert(_normalizeLineEndings(content));
    final startIndex = lines.indexWhere(
      (line) => RegExp(r'^[ \t]*tunnels:\s*(?:\{\})?\s*$').hasMatch(line),
    );
    final replacementLines =
        const LineSplitter().convert(replacement.trimRight());

    if (startIndex == -1) {
      final trimmed = content.trimRight();
      if (trimmed.isEmpty) {
        return replacement.trimRight();
      }
      return '$trimmed\n\n${replacement.trimRight()}';
    }

    var endIndex = startIndex + 1;
    while (endIndex < lines.length) {
      final line = lines[endIndex];
      final trimmed = line.trimLeft();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        endIndex++;
        continue;
      }
      if (!line.startsWith(' ') && !line.startsWith('\t')) {
        break;
      }
      endIndex++;
    }

    final updatedLines = <String>[
      ...lines.take(startIndex),
      ...replacementLines,
      ...lines.skip(endIndex),
    ];
    return updatedLines.join('\n');
  }

  static String _normalizeLineEndings(String value) {
    return value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  static String? _readConfigValue(String content, String key) {
    final match = RegExp(
      '^[ \\t]*${RegExp.escape(key)}:\\s*(.+?)\\s*\$',
      multiLine: true,
    ).firstMatch(content);
    final value = match?.group(1)?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return _unquoteYamlScalar(value);
  }

  static int? _parsePortValue(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final directPort = int.tryParse(value);
    if (directPort != null) {
      return directPort;
    }
    final match = RegExp(r':(\d+)$').firstMatch(value);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1)!);
  }

  static String _withAuthtoken(String content, String? authtoken) {
    return _ensureTrailingNewline(
      _upsertAuthtoken(
        content,
        authtoken?.trim().isNotEmpty == true ? authtoken : null,
      ).trimRight(),
    );
  }

  static String _yamlSingleQuoted(String value) {
    return "'${value.replaceAll("'", "''")}'";
  }

  static String _unquoteYamlScalar(String value) {
    if (value.length >= 2 &&
        ((value.startsWith("'") && value.endsWith("'")) ||
            (value.startsWith('"') && value.endsWith('"')))) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }

  static String? _downloadUrlForArch(String arch) {
    switch (arch) {
      case 'aarch64':
        return 'http://www.cpolar.com/static/downloads/releases/$_cpolarVersion/cpolar-stable-linux-arm64.zip';
      case 'arm':
        return 'http://www.cpolar.com/static/downloads/releases/$_cpolarVersion/cpolar-stable-linux-arm.zip';
      case 'x86_64':
        return 'http://www.cpolar.com/static/downloads/releases/$_cpolarVersion/cpolar-stable-linux-amd64.zip';
      case 'x86':
        return 'http://www.cpolar.com/static/downloads/releases/$_cpolarVersion/cpolar-stable-linux-386.zip';
      default:
        return null;
    }
  }

  static String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }
}
