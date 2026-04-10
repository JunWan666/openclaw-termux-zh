import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../l10n/app_localizations.dart';
import '../constants.dart';
import '../services/dashboard_url_resolver.dart';
import '../services/gateway_auth_config_service.dart';
import '../services/preferences_service.dart';

class WebDashboardScreen extends StatefulWidget {
  final String? url;

  const WebDashboardScreen({super.key, this.url});

  @override
  State<WebDashboardScreen> createState() => _WebDashboardScreenState();
}

class _WebDashboardScreenState extends State<WebDashboardScreen> {
  static const _loadTimeout = Duration(seconds: 12);
  static const _postLoadProbeDelay = Duration(milliseconds: 1400);

  late final WebViewController _controller;
  final WebViewCookieManager _cookieManager = WebViewCookieManager();

  Timer? _loadTimer;
  bool _loading = true;
  String? _error;
  String? _statusMessage;
  String? _currentUrl;
  List<String> _candidateUrls = const [];
  int _currentCandidateIndex = 0;
  int _navigationRevision = 0;
  double _pageScale = 1.0;

  @override
  void initState() {
    super.initState();
    _controller = _createWebViewController();
    unawaited(_initializeScreen());
  }

  Future<void> _initializeScreen() async {
    final prefs = PreferencesService();
    await prefs.init();
    if (!mounted) {
      return;
    }

    final savedScale = prefs.webDashboardScale;
    if ((_pageScale - savedScale).abs() > 0.0001) {
      setState(() {
        _pageScale = savedScale;
      });
    }

    await _loadUrl();
  }

  WebViewController _createWebViewController() {
    const controllerCreationParams = PlatformWebViewControllerCreationParams();
    final controller = WebViewController.fromPlatformCreationParams(
      controllerCreationParams,
    )
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(true)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!_matchesCurrentNavigation(url)) {
              return;
            }
            _startLoadTimer();
            if (mounted) {
              setState(() {
                _loading = true;
                _error = null;
              });
            }
          },
          onPageFinished: (url) {
            if (!_matchesCurrentNavigation(url)) {
              return;
            }
            _cancelLoadTimer();
            if (mounted) {
              setState(() {
                _loading = false;
                if (_currentCandidateIndex == 0) {
                  _statusMessage = null;
                } else if (_currentUrl != null) {
                  _statusMessage =
                      'Using ${Uri.parse(_currentUrl!).host} fallback.';
                }
              });
            }
            unawaited(_applyPageScale());
            unawaited(_runPostLoadProbe(_navigationRevision, url));
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == false) {
              return;
            }
            if (!_matchesCurrentNavigation(error.url)) {
              return;
            }
            if (mounted) {
              unawaited(
                _handleLoadProblem(
                  reason:
                      'Failed to load dashboard: ${error.description.trim()}',
                  allowFallback: true,
                ),
              );
            }
          },
        ),
      );

    final platformController = controller.platform;
    if (platformController is AndroidWebViewController) {
      unawaited(platformController.setUseWideViewPort(true));
      unawaited(platformController.setTextZoom(100));
      unawaited(
          platformController.setMixedContentMode(MixedContentMode.alwaysAllow));
      unawaited(platformController.setHorizontalScrollBarEnabled(true));
      unawaited(platformController.setVerticalScrollBarEnabled(true));
    }

    return controller;
  }

  WebViewWidget _buildWebViewWidget() {
    final platformController = _controller.platform;
    if (platformController is AndroidWebViewController) {
      final params = AndroidWebViewWidgetCreationParams(
        controller: platformController,
        displayWithHybridComposition: true,
      );
      return WebViewWidget.fromPlatformCreationParams(params: params);
    }

    return WebViewWidget(controller: _controller);
  }

  @override
  void dispose() {
    _cancelLoadTimer();
    super.dispose();
  }

  Future<void> _loadUrl() async {
    var url = widget.url;
    if (url == null || url.isEmpty) {
      // Fallback: load saved token URL from preferences
      final prefs = PreferencesService();
      await prefs.init();
      url = prefs.dashboardUrl;
    }
    var resolvedUrl = DashboardUrlResolver.normalizeDashboardUrl(
      url,
      baseUri: Uri.parse(AppConstants.gatewayUrl),
    );

    if (!DashboardUrlResolver.hasToken(resolvedUrl)) {
      final configuredUrl = await GatewayAuthConfigService.readDashboardUrl(
        baseUri: Uri.parse(AppConstants.gatewayUrl),
      );
      if (configuredUrl != null && configuredUrl.isNotEmpty) {
        resolvedUrl = configuredUrl;
      }
    }

    resolvedUrl ??= AppConstants.gatewayUrl;
    final candidates = _buildCandidateUrls(resolvedUrl);
    if (!mounted) {
      return;
    }

    setState(() {
      _candidateUrls = candidates;
      _currentCandidateIndex = 0;
      _statusMessage = null;
    });

    await _loadCandidate(0, clearState: true);
  }

  List<String> _buildCandidateUrls(String resolvedUrl) {
    final uri = Uri.tryParse(resolvedUrl);
    if (uri == null) {
      return [resolvedUrl];
    }

    final candidates = <String>[];

    void add(Uri value) {
      final text = value.toString();
      if (!candidates.contains(text)) {
        candidates.add(text);
      }
    }

    add(uri);

    if (uri.host == '127.0.0.1') {
      add(uri.replace(host: 'localhost'));
    } else if (uri.host == 'localhost') {
      add(uri.replace(host: '127.0.0.1'));
    }

    return candidates;
  }

  bool _matchesCurrentNavigation(String? url) {
    final current = _currentUrl;
    if (url == null || url.isEmpty || current == null || current.isEmpty) {
      return true;
    }

    final normalizedCurrent = DashboardUrlResolver.normalizeDashboardUrl(
      current,
      baseUri: Uri.parse(AppConstants.gatewayUrl),
    );
    final normalizedUrl = DashboardUrlResolver.normalizeDashboardUrl(
      url,
      baseUri: Uri.parse(AppConstants.gatewayUrl),
    );

    if (normalizedCurrent == normalizedUrl) {
      return true;
    }

    final currentUri = Uri.tryParse(normalizedCurrent ?? current);
    final finishedUri = Uri.tryParse(normalizedUrl ?? url);
    if (currentUri == null || finishedUri == null) {
      return false;
    }

    return currentUri.host == finishedUri.host &&
        currentUri.port == finishedUri.port;
  }

  Future<void> _loadCandidate(
    int index, {
    required bool clearState,
    String? statusMessage,
  }) async {
    if (index < 0 || index >= _candidateUrls.length) {
      return;
    }

    final targetUrl = _candidateUrls[index];
    final currentRevision = ++_navigationRevision;

    if (mounted) {
      setState(() {
        _currentCandidateIndex = index;
        _currentUrl = targetUrl;
        _statusMessage = statusMessage;
        _loading = true;
        _error = null;
      });
    }

    if (clearState) {
      await _resetWebViewState();
      if (!mounted || currentRevision != _navigationRevision) {
        return;
      }
    }

    _startLoadTimer();

    try {
      await _controller.loadRequest(Uri.parse(targetUrl));
    } catch (e) {
      if (!mounted || currentRevision != _navigationRevision) {
        return;
      }
      await _handleLoadProblem(
        reason: 'Failed to open dashboard URL: $e',
        allowFallback: true,
      );
    }
  }

  Future<void> _reloadCurrentCandidate() async {
    if (_candidateUrls.isEmpty) {
      await _loadUrl();
      return;
    }

    await _loadCandidate(
      _currentCandidateIndex,
      clearState: true,
      statusMessage: 'Reloading dashboard...',
    );
  }

  Future<void> _switchLocalAddress() async {
    if (_candidateUrls.length < 2) {
      return;
    }

    final nextIndex = (_currentCandidateIndex + 1) % _candidateUrls.length;
    if (nextIndex == _currentCandidateIndex) {
      return;
    }

    final host = Uri.tryParse(_candidateUrls[nextIndex])?.host ??
        _candidateUrls[nextIndex];
    await _loadCandidate(
      nextIndex,
      clearState: true,
      statusMessage: 'Switching to $host...',
    );
  }

  Future<void> _openInExternalBrowser() async {
    final targetUrl = _currentUrl ??
        (_candidateUrls.isNotEmpty
            ? _candidateUrls[_currentCandidateIndex]
            : null);
    if (targetUrl == null) {
      return;
    }

    final uri = Uri.tryParse(targetUrl);
    if (uri == null) {
      _showSnackBar('Invalid dashboard URL.');
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      _showSnackBar('Unable to open the external browser.');
    }
  }

  Future<void> _setPageScale(double? requestedScale) async {
    final scale = requestedScale ?? 1.0;
    if (mounted) {
      setState(() {
        _pageScale = scale;
      });
    }
    final prefs = PreferencesService();
    await prefs.init();
    prefs.webDashboardScale = scale;
    await _applyPageScale();
    if (!mounted) {
      return;
    }
    if (requestedScale == null) {
      _showSnackBar('Adaptive view enabled.');
    } else {
      _showSnackBar('Page scale set to ${(scale * 100).round()}%.');
    }
  }

  Future<void> _applyPageScale() async {
    final scale = _pageScale;
    try {
      await _controller.runJavaScript('''
(() => {
  const requestedScale = ${scale.toStringAsFixed(2)};
  const root = document.documentElement;
  const body = document.body;
  if (!root) return;

  let safeScale = Math.min(Math.max(requestedScale, 0.2), 1.0);

  // Clear legacy CSS zoom overrides first. They were shrinking the page
  // inside the same viewport, which made the height collapse and left
  // large blank space at the bottom on phones.
  root.style.zoom = '';
  root.style.width = '';
  root.style.minHeight = '100%';
  root.style.overflow = '';

  if (body) {
    body.style.zoom = '';
    body.style.width = '';
    body.style.minHeight = '100%';
    body.style.overflow = '';
  }

  if (requestedScale >= 0.999) {
    const viewportWidth =
        window.visualViewport?.width || window.innerWidth || root.clientWidth || 0;
    const contentWidth = Math.max(
      root.scrollWidth || 0,
      root.clientWidth || 0,
      body?.scrollWidth || 0,
      body?.clientWidth || 0
    );

    if (viewportWidth > 0 && contentWidth > viewportWidth * 1.02) {
      safeScale = Math.min(1.0, Math.max(0.2, viewportWidth / contentWidth));
    }
  }

  let meta = document.querySelector('meta[name="viewport"]');
  if (!meta) {
    meta = document.createElement('meta');
    meta.setAttribute('name', 'viewport');
    document.head.appendChild(meta);
  }

  const targetContent = [
    'width=device-width',
    'initial-scale=' + safeScale.toFixed(2),
    'minimum-scale=0.20',
    'maximum-scale=5.00',
    'user-scalable=yes',
    'viewport-fit=cover'
  ].join(', ');

  if (meta.getAttribute('content') !== targetContent) {
    meta.setAttribute('content', targetContent);
  }

  // Nudge layout after viewport changes so responsive pages re-measure.
  window.dispatchEvent(new Event('resize'));
  window.scrollTo(0, 0);
})();
''');
    } catch (_) {
      // Ignore manual scale failures and keep the original page layout.
    }
  }

  Future<void> _resetWebViewState() async {
    try {
      await _controller.clearCache();
    } catch (_) {}

    try {
      await _controller.clearLocalStorage();
    } catch (_) {}

    try {
      await _cookieManager.clearCookies();
    } catch (_) {}
  }

  void _startLoadTimer() {
    _cancelLoadTimer();
    _loadTimer = Timer(_loadTimeout, () {
      if (!_loading) {
        return;
      }
      unawaited(
        _handleLoadProblem(
          reason: 'The embedded dashboard took too long to respond.',
          allowFallback: true,
        ),
      );
    });
  }

  void _cancelLoadTimer() {
    _loadTimer?.cancel();
    _loadTimer = null;
  }

  Future<void> _handleLoadProblem({
    required String reason,
    required bool allowFallback,
  }) async {
    _cancelLoadTimer();

    if (allowFallback) {
      final switched = await _tryNextCandidate(reason: reason);
      if (switched) {
        return;
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _loading = false;
      _error = reason;
      _statusMessage = null;
    });
  }

  Future<bool> _tryNextCandidate({required String reason}) async {
    final nextIndex = _currentCandidateIndex + 1;
    if (nextIndex >= _candidateUrls.length) {
      return false;
    }

    final nextHost = Uri.tryParse(_candidateUrls[nextIndex])?.host ??
        _candidateUrls[nextIndex];
    await _loadCandidate(
      nextIndex,
      clearState: true,
      statusMessage: '$reason Trying $nextHost...',
    );
    return true;
  }

  Future<void> _runPostLoadProbe(int revision, String finishedUrl) async {
    await Future<void>.delayed(_postLoadProbeDelay);
    if (!mounted || revision != _navigationRevision) {
      return;
    }

    final snapshot = await _readDomSnapshot();
    if (!mounted || revision != _navigationRevision || snapshot == null) {
      return;
    }

    if (snapshot.looksBlank) {
      await _handleLoadProblem(
        reason: 'The dashboard loaded but stayed blank.',
        allowFallback: true,
      );
      return;
    }

    if (_currentUrl == finishedUrl && mounted && _currentCandidateIndex > 0) {
      setState(() {
        _statusMessage = 'Loaded with ${Uri.parse(finishedUrl).host}.';
      });
    }
  }

  Future<_DashboardDomSnapshot?> _readDomSnapshot() async {
    try {
      final raw = await _controller.runJavaScriptReturningResult('''
(() => {
  const body = document.body;
  return JSON.stringify({
    readyState: document.readyState || '',
    title: document.title || '',
    textLength: (body?.innerText || '').trim().length,
    htmlLength: (body?.innerHTML || '').length,
    childCount: body?.children?.length || 0
  });
})();
''');
      final normalized = _normalizeJavaScriptStringResult(raw);
      if (normalized == null || normalized.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(normalized);
      if (decoded is Map<String, dynamic>) {
        return _DashboardDomSnapshot.fromJson(decoded);
      }
      if (decoded is Map) {
        return _DashboardDomSnapshot.fromJson(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String? _normalizeJavaScriptStringResult(Object raw) {
    final text = raw.toString().trim();
    if (text.isEmpty) {
      return null;
    }

    if ((text.startsWith('"') && text.endsWith('"')) ||
        (text.startsWith("'") && text.endsWith("'"))) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is String) {
          return decoded;
        }
      } catch (_) {}
    }

    return text;
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('dashboardWebDashboardTitle')),
        actions: [
          PopupMenuButton<double?>(
            icon: const Icon(Icons.zoom_out_map),
            tooltip: 'Page scale',
            onSelected: _setPageScale,
            itemBuilder: (context) => const [
              PopupMenuItem<double?>(value: null, child: Text('Adaptive')),
              PopupMenuItem<double?>(value: 0.85, child: Text('85%')),
              PopupMenuItem<double?>(value: 0.75, child: Text('75%')),
              PopupMenuItem<double?>(value: 0.5, child: Text('50%')),
              PopupMenuItem<double?>(value: 0.33, child: Text('33%')),
              PopupMenuItem<double?>(value: 0.25, child: Text('25%')),
              PopupMenuItem<double?>(value: 0.2, child: Text('20%')),
            ],
          ),
          if (_candidateUrls.length > 1)
            IconButton(
              icon: const Icon(Icons.swap_horiz),
              tooltip: 'Switch local address',
              onPressed: _switchLocalAddress,
            ),
          IconButton(
            icon: const Icon(Icons.open_in_browser_outlined),
            tooltip: l10n.t('gatewayOpenDashboard'),
            onPressed: _openInExternalBrowser,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.t('logsRefresh'),
            onPressed: _reloadCurrentCandidate,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_statusMessage != null)
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                if (_error != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.wifi_off,
                            size: 48,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            alignment: WrapAlignment.center,
                            children: [
                              FilledButton.icon(
                                onPressed: _reloadCurrentCandidate,
                                icon: const Icon(Icons.refresh),
                                label: Text(l10n.t('commonRetry')),
                              ),
                              OutlinedButton.icon(
                                onPressed: _openInExternalBrowser,
                                icon:
                                    const Icon(Icons.open_in_browser_outlined),
                                label: Text(l10n.t('gatewayOpenDashboard')),
                              ),
                              if (_candidateUrls.length > 1)
                                OutlinedButton.icon(
                                  onPressed: _switchLocalAddress,
                                  icon: const Icon(Icons.swap_horiz),
                                  label: const Text('Switch host'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  _buildWebViewWidget(),
                if (_loading) const LinearProgressIndicator(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardDomSnapshot {
  const _DashboardDomSnapshot({
    required this.readyState,
    required this.title,
    required this.textLength,
    required this.htmlLength,
    required this.childCount,
  });

  factory _DashboardDomSnapshot.fromJson(Map<String, dynamic> json) {
    return _DashboardDomSnapshot(
      readyState: (json['readyState'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      textLength: _parseInt(json['textLength']),
      htmlLength: _parseInt(json['htmlLength']),
      childCount: _parseInt(json['childCount']),
    );
  }

  final String readyState;
  final String title;
  final int textLength;
  final int htmlLength;
  final int childCount;

  bool get looksBlank {
    if (readyState != 'complete') {
      return false;
    }

    return title.trim().isEmpty &&
        textLength < 8 &&
        htmlLength < 1200 &&
        childCount <= 1;
  }

  static int _parseInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
