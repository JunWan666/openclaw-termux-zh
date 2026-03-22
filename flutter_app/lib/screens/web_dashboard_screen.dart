import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../constants.dart';
import '../services/preferences_service.dart';

class WebDashboardScreen extends StatefulWidget {
  final String? url;

  const WebDashboardScreen({super.key, this.url});

  @override
  State<WebDashboardScreen> createState() => _WebDashboardScreenState();
}

class _WebDashboardScreenState extends State<WebDashboardScreen> {
  static const _dashboardZoomScale = 0.5;
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            _applyDefaultZoom();
            Future.delayed(
              const Duration(milliseconds: 400),
              _applyDefaultZoom,
            );
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() {
                _loading = false;
                _error = 'Failed to load dashboard: ${error.description}';
              });
            }
          },
        ),
      );
    _loadUrl();
  }

  Future<void> _loadUrl() async {
    var url = widget.url;
    if (url == null || url.isEmpty) {
      // Fallback: load saved token URL from preferences
      final prefs = PreferencesService();
      await prefs.init();
      url = prefs.dashboardUrl;
    }
    _controller.loadRequest(Uri.parse(url ?? AppConstants.gatewayUrl));
  }

  Future<void> _applyDefaultZoom() async {
    try {
      await _controller.runJavaScript('''
(() => {
  const scale = $_dashboardZoomScale;
  const root = document.documentElement;
  const head = document.head || document.getElementsByTagName('head')[0];
  const body = document.body;
  if (!root || !head) return;

  let viewport = document.querySelector('meta[name="viewport"]');
  if (!viewport) {
    viewport = document.createElement('meta');
    viewport.setAttribute('name', 'viewport');
    head.appendChild(viewport);
  }

  viewport.setAttribute(
    'content',
    [
      'width=device-width',
      'initial-scale=' + scale,
      'minimum-scale=' + scale,
      'maximum-scale=5',
      'user-scalable=yes',
      'viewport-fit=cover'
    ].join(', ')
  );

  root.style.width = '100%';
  root.style.maxWidth = '100%';
  root.style.overflowX = 'hidden';
  root.style.webkitTextSizeAdjust = '100%';

  if (!body) return;

  body.style.zoom = '';
  body.style.transform = '';
  body.style.transformOrigin = '';
  body.style.width = '100%';
  body.style.maxWidth = '100%';
  body.style.minWidth = '100%';
  body.style.minHeight = '100%';
  body.style.margin = '0';
  body.style.overflowX = 'hidden';
})();
''');
    } catch (_) {
      // Ignore zoom injection failures and show the page normally.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Web Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _error = null;
                _loading = true;
              });
              _controller.reload();
            },
          ),
        ],
      ),
      body: Stack(
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
                    FilledButton.icon(
                      onPressed: () {
                        setState(() {
                          _error = null;
                          _loading = true;
                        });
                        _controller.reload();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else
            WebViewWidget(controller: _controller),
          if (_loading) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
