import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../l10n/app_localizations.dart';
import '../providers/gateway_provider.dart';
import '../services/native_bridge.dart';
import '../services/screenshot_service.dart';

enum _LogSource { gateway, conversation }

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _screenshotKey = GlobalKey();

  bool _autoScroll = true;
  String _filter = '';
  _LogSource _source = _LogSource.gateway;
  bool _loadingConversationLogs = false;
  String? _conversationLogFile;
  String? _conversationLogError;
  List<String> _conversationLogs = const [];

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadConversationLogs() async {
    setState(() {
      _loadingConversationLogs = true;
      _conversationLogError = null;
    });

    try {
      final output = await NativeBridge.runInProot(
        r'''
latest="$(ls -1t /root/.openclaw/agents/main/sessions/*.jsonl 2>/dev/null | head -n 1)"
if [ -n "$latest" ]; then
  printf '__OPENCLAW_SESSION_FILE__%s\n' "$latest"
  cat "$latest"
fi
''',
        timeout: 60,
      );

      final lines = const LineSplitter().convert(output);
      String? filePath;
      if (lines.isNotEmpty &&
          lines.first.startsWith('__OPENCLAW_SESSION_FILE__')) {
        filePath =
            lines.first.replaceFirst('__OPENCLAW_SESSION_FILE__', '').trim();
      }

      if (!mounted) return;
      setState(() {
        _conversationLogFile = filePath;
        _conversationLogs =
            filePath == null ? const [] : lines.skip(1).toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _conversationLogError = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loadingConversationLogs = false);
      }
    }
  }

  Future<void> _switchSource(_LogSource source) async {
    if (_source == source) return;

    setState(() => _source = source);
    if (source == _LogSource.conversation) {
      await _loadConversationLogs();
    }
  }

  List<String> _currentLogs(BuildContext context) {
    if (_source == _LogSource.conversation) {
      return _conversationLogs;
    }
    return context.read<GatewayProvider>().state.logs;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final gatewayHasLogs = context.select<GatewayProvider, bool>(
      (provider) => provider.state.logs.isNotEmpty,
    );
    final currentLogs = _source == _LogSource.conversation
        ? _conversationLogs
        : context.select<GatewayProvider, List<String>>(
            (provider) => provider.state.logs,
          );
    final filtered = _filter.isEmpty
        ? currentLogs
        : currentLogs
            .where((line) => line.toLowerCase().contains(_filter.toLowerCase()))
            .toList();
    final hasLogs = currentLogs.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('logsTitle')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.t('logsRefresh'),
            onPressed:
                _source == _LogSource.conversation && !_loadingConversationLogs
                    ? _loadConversationLogs
                    : null,
          ),
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            tooltip: l10n.t('commonScreenshot'),
            onPressed: _takeScreenshot,
          ),
          IconButton(
            icon: Icon(
              _autoScroll
                  ? Icons.vertical_align_bottom
                  : Icons.vertical_align_top,
            ),
            tooltip: _autoScroll
                ? l10n.t('logsAutoScrollOn')
                : l10n.t('logsAutoScrollOff'),
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: l10n.t('logsCopyAll'),
            onPressed: hasLogs ? () => _copyLogs(context) : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: l10n.t('logsClear'),
            onPressed: _source == _LogSource.gateway && gatewayHasLogs
                ? () => _clearLogs(context)
                : null,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<_LogSource>(
                segments: [
                  ButtonSegment<_LogSource>(
                    value: _LogSource.gateway,
                    label: Text(l10n.t('logsTypeGateway')),
                    icon: const Icon(Icons.settings_input_component_outlined),
                  ),
                  ButtonSegment<_LogSource>(
                    value: _LogSource.conversation,
                    label: Text(l10n.t('logsTypeConversation')),
                    icon: const Icon(Icons.chat_bubble_outline),
                  ),
                ],
                selected: {_source},
                onSelectionChanged: (selection) {
                  final nextSource = selection.first;
                  _switchSource(nextSource);
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.t('logsFilterHint'),
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                suffixIcon: _filter.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _filter = '');
                        },
                      )
                    : null,
              ),
              onChanged: (value) => setState(() => _filter = value),
            ),
          ),
          if (_source == _LogSource.conversation &&
              _conversationLogFile != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.t('logsSessionFileHint', {'path': _conversationLogFile}),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFamily: 'DejaVuSansMono',
                  ),
                ),
              ),
            ),
          Expanded(
            child: RepaintBoundary(
              key: _screenshotKey,
              child: Builder(
                builder: (context) {
                  if (_source == _LogSource.conversation &&
                      _loadingConversationLogs) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(l10n.t('logsConversationLoading')),
                        ],
                      ),
                    );
                  }

                  if (_source == _LogSource.conversation &&
                      _conversationLogError != null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l10n.t('logsConversationLoadFailed', {
                            'error': _conversationLogError,
                          }),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    );
                  }

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        _filter.isNotEmpty
                            ? l10n.t('logsNoMatch')
                            : _emptyStateText(l10n),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_autoScroll && _scrollController.hasClients) {
                      _scrollController.jumpTo(
                        _scrollController.position.maxScrollExtent,
                      );
                    }
                  });

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final line = filtered[index];
                      return Text(
                        line,
                        style: TextStyle(
                          fontFamily: 'DejaVuSansMono',
                          fontSize: 12,
                          color: _logColor(line, theme),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _emptyStateText(AppLocalizations l10n) {
    switch (_source) {
      case _LogSource.gateway:
        return l10n.t('logsEmpty');
      case _LogSource.conversation:
        return l10n.t('logsConversationEmpty');
    }
  }

  Color _logColor(String line, ThemeData theme) {
    if (line.contains('[ERR]') ||
        line.contains('ERROR') ||
        line.contains('"level":"error"')) {
      return theme.colorScheme.error;
    }
    if (line.contains('[WARN]') ||
        line.contains('WARNING') ||
        line.contains('"level":"warn"')) {
      return AppColors.statusAmber;
    }
    if (line.contains('[INFO]') || line.contains('"level":"info"')) {
      return AppColors.mutedText;
    }
    return theme.colorScheme.onSurface;
  }

  Future<void> _takeScreenshot() async {
    final path =
        await ScreenshotService.capture(_screenshotKey, prefix: 'logs');
    if (!mounted) return;
    final l10n = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          path != null
              ? l10n.t('commonScreenshotSaved', {
                  'fileName': path.split('/').last,
                })
              : l10n.t('commonSaveFailed'),
        ),
      ),
    );
  }

  void _copyLogs(BuildContext context) {
    final text = _currentLogs(context).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.t('logsCopied'))),
    );
  }

  Future<void> _clearLogs(BuildContext context) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.t('logsClearConfirmTitle')),
        content: Text(l10n.t('logsClearConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.t('commonCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.t('logsClear')),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    context.read<GatewayProvider>().clearLogs();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.t('logsCleared'))),
    );
  }
}
