import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  static const _conversationSessionsRelativePath =
      'root/.openclaw/agents/main/sessions';
  static const _conversationSessionsDisplayPath =
      '/root/.openclaw/agents/main/sessions';

  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  final _screenshotKey = GlobalKey();

  Timer? _conversationRefreshTimer;
  bool _autoScroll = true;
  bool _loadingConversationLogs = false;
  bool _conversationLoadInFlight = false;
  bool _showJumpToBottom = false;
  String _filter = '';
  String _lastAutoScrollSignature = '';
  _LogSource _source = _LogSource.gateway;
  String? _conversationLogFile;
  String? _conversationLogError;
  List<String> _conversationLogs = const [];
  List<_ConversationRecord> _conversationRecords = const [];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScrollChanged);
  }

  @override
  void dispose() {
    _conversationRefreshTimer?.cancel();
    _scrollController.removeListener(_handleScrollChanged);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _setConversationRefreshEnabled(bool enabled) {
    _conversationRefreshTimer?.cancel();
    if (!enabled) return;
    _conversationRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _source != _LogSource.conversation) return;
      _loadConversationLogs(silent: true);
    });
  }

  Future<File?> _findLatestConversationLogFile() async {
    final filesDir = await NativeBridge.getFilesDir();
    final sessionsDir =
        Directory('$filesDir/rootfs/ubuntu/$_conversationSessionsRelativePath');
    if (!await sessionsDir.exists()) {
      return null;
    }

    final jsonlFiles = <File>[];
    await for (final entry in sessionsDir.list(followLinks: false)) {
      if (entry is File && entry.path.toLowerCase().endsWith('.jsonl')) {
        jsonlFiles.add(entry);
      }
    }

    if (jsonlFiles.isEmpty) {
      return null;
    }

    final stampedFiles = <({File file, DateTime modifiedAt})>[];
    for (final file in jsonlFiles) {
      try {
        stampedFiles.add((file: file, modifiedAt: await file.lastModified()));
      } catch (_) {
        // Ignore files that disappear between listing and stat.
      }
    }

    if (stampedFiles.isEmpty) {
      return null;
    }

    stampedFiles.sort((left, right) {
      final modifiedCompare = right.modifiedAt.compareTo(left.modifiedAt);
      if (modifiedCompare != 0) {
        return modifiedCompare;
      }
      return right.file.path.compareTo(left.file.path);
    });
    return stampedFiles.first.file;
  }

  String _displayConversationLogPath(File file) {
    return '$_conversationSessionsDisplayPath/${file.uri.pathSegments.last}';
  }

  Future<void> _loadConversationLogs({bool silent = false}) async {
    if (_conversationLoadInFlight) return;
    _conversationLoadInFlight = true;

    final showLoadingState = !silent || _conversationRecords.isEmpty;
    if (showLoadingState && mounted) {
      setState(() {
        _loadingConversationLogs = true;
        if (!silent) {
          _conversationLogError = null;
        }
      });
    }

    try {
      final latestFile = await _findLatestConversationLogFile();
      final rawLogs = latestFile == null
          ? const <String>[]
          : const LineSplitter()
              .convert(await latestFile.readAsString())
              .where((line) => line.trim().isNotEmpty)
              .toList(growable: false);
      final filePath =
          latestFile == null ? null : _displayConversationLogPath(latestFile);

      if (!mounted) return;
      setState(() {
        _conversationLogFile = filePath;
        _conversationLogs = rawLogs;
        _conversationRecords =
            rawLogs.map(_ConversationRecord.parse).toList(growable: false);
        _conversationLogError = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent || _conversationRecords.isEmpty) {
        setState(() => _conversationLogError = e.toString());
      }
    } finally {
      _conversationLoadInFlight = false;
      if (mounted && showLoadingState) {
        setState(() => _loadingConversationLogs = false);
      }
    }
  }

  Future<void> _switchSource(_LogSource source) async {
    if (_source == source) return;

    setState(() {
      _source = source;
      _lastAutoScrollSignature = '';
    });

    if (source == _LogSource.conversation) {
      _setConversationRefreshEnabled(true);
      await _loadConversationLogs();
    } else {
      _setConversationRefreshEnabled(false);
    }
  }

  void _toggleAutoScroll() {
    setState(() {
      _autoScroll = !_autoScroll;
      _lastAutoScrollSignature = '';
    });
    if (_autoScroll) {
      _scheduleScrollToBottom(force: true);
    }
  }

  void _maybeScheduleAutoScroll(String signature, {required bool hasContent}) {
    if (!_autoScroll || !hasContent || _lastAutoScrollSignature == signature) {
      return;
    }
    _lastAutoScrollSignature = signature;
    _scheduleScrollToBottom();
  }

  void _scheduleScrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshJumpToBottomVisibility();
      _scrollToBottom(force: force, animate: true);
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        _scrollToBottom(force: force);
        _refreshJumpToBottomVisibility();
      });
      Future<void>.delayed(const Duration(milliseconds: 320), () {
        if (!mounted) return;
        _scrollToBottom(force: force);
        _refreshJumpToBottomVisibility();
      });
    });
  }

  void _scrollToBottom({bool force = false, bool animate = false}) {
    if (!mounted || !_scrollController.hasClients) return;
    if (!_autoScroll && !force) return;

    final position = _scrollController.position;
    final maxScroll = position.maxScrollExtent;
    if (!maxScroll.isFinite) return;

    final distanceToBottom = maxScroll - position.pixels;
    if (!force && distanceToBottom.abs() < 2) return;

    if (animate) {
      _scrollController.animateTo(
        maxScroll,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    _scrollController.jumpTo(maxScroll);
  }

  void _handleScrollChanged() {
    _refreshJumpToBottomVisibility();
  }

  void _refreshJumpToBottomVisibility() {
    if (!mounted || !_scrollController.hasClients) return;
    final shouldShow = _scrollController.position.extentAfter > 80;
    if (shouldShow != _showJumpToBottom) {
      setState(() => _showJumpToBottom = shouldShow);
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
    final gatewayLogs = context.select<GatewayProvider, List<String>>(
      (provider) => provider.state.logs,
    );
    final currentLogs =
        _source == _LogSource.conversation ? _conversationLogs : gatewayLogs;
    final filteredGatewayLogs = _filter.isEmpty
        ? currentLogs
        : currentLogs
            .where((line) => line.toLowerCase().contains(_filter.toLowerCase()))
            .toList(growable: false);
    final filteredConversationRecords = _filter.isEmpty
        ? _conversationRecords
        : _conversationRecords
            .where(
              (record) => record.searchText
                  .toLowerCase()
                  .contains(_filter.toLowerCase()),
            )
            .toList(growable: false);
    final visibleCount = _source == _LogSource.conversation
        ? filteredConversationRecords.length
        : filteredGatewayLogs.length;
    final lastSignature = _source == _LogSource.conversation
        ? (filteredConversationRecords.isEmpty
            ? 'none'
            : filteredConversationRecords.last.signature)
        : (filteredGatewayLogs.isEmpty ? 'none' : filteredGatewayLogs.last);

    _maybeScheduleAutoScroll(
      '${_source.name}|$visibleCount|$lastSignature|$_filter',
      hasContent: visibleCount > 0,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('logsTitle')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.t('logsRefresh'),
            onPressed:
                _source == _LogSource.conversation && !_conversationLoadInFlight
                    ? () => _loadConversationLogs()
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
            onPressed: _toggleAutoScroll,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: l10n.t('logsCopyAll'),
            onPressed: currentLogs.isNotEmpty ? () => _copyLogs(context) : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: l10n.t('logsClear'),
            onPressed: _source == _LogSource.gateway && gatewayLogs.isNotEmpty
                ? () => _clearLogs(context)
                : null,
          ),
        ],
      ),
      floatingActionButton:
          visibleCount > 0 && (_showJumpToBottom || !_autoScroll)
              ? FloatingActionButton.small(
                  heroTag: 'logs-jump-to-latest',
                  tooltip: _jumpToLatestLabel(context),
                  onPressed: () => _scheduleScrollToBottom(force: true),
                  child: const Icon(Icons.arrow_downward_rounded),
                )
              : null,
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
                  _switchSource(selection.first);
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
                          setState(() {
                            _filter = '';
                            _lastAutoScrollSignature = '';
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() {
                  _filter = value;
                  _lastAutoScrollSignature = '';
                });
              },
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
              child: _buildBody(
                context,
                theme,
                l10n,
                filteredGatewayLogs,
                filteredConversationRecords,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
    List<String> filteredGatewayLogs,
    List<_ConversationRecord> filteredConversationRecords,
  ) {
    if (_source == _LogSource.conversation &&
        _loadingConversationLogs &&
        _conversationRecords.isEmpty) {
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
        _conversationLogError != null &&
        _conversationRecords.isEmpty) {
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

    if (_source == _LogSource.conversation) {
      if (filteredConversationRecords.isEmpty) {
        return Center(
          child: Text(
            _filter.isNotEmpty ? l10n.t('logsNoMatch') : _emptyStateText(l10n),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
      }
      return _buildConversationList(
          context, theme, l10n, filteredConversationRecords);
    }

    if (filteredGatewayLogs.isEmpty) {
      return Center(
        child: Text(
          _filter.isNotEmpty ? l10n.t('logsNoMatch') : _emptyStateText(l10n),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 80),
      itemCount: filteredGatewayLogs.length,
      itemBuilder: (context, index) {
        final line = filteredGatewayLogs[index];
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
  }

  Widget _buildConversationList(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
    List<_ConversationRecord> records,
  ) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final showRefreshError =
        _conversationLogError != null && _conversationRecords.isNotEmpty;

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
      itemCount: records.length + (showRefreshError ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        var itemIndex = index;
        if (showRefreshError) {
          if (itemIndex == 0) {
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withAlpha(170),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                isZh
                    ? '鑷姩鍒锋柊澶辫触锛?{_conversationLogError ?? ' '}'
                    : 'Auto refresh failed: $_conversationLogError',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            );
          }
          itemIndex -= 1;
        }

        final record = records[itemIndex];
        switch (record.kind) {
          case _ConversationRecordKind.session:
          case _ConversationRecordKind.event:
            return _buildConversationMetaCard(context, theme, record);
          case _ConversationRecordKind.message:
            return _buildConversationMessage(context, theme, record);
          case _ConversationRecordKind.raw:
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.outline.withAlpha(35),
                ),
              ),
              child: SelectableText(
                record.rawLine,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'DejaVuSansMono',
                  height: 1.45,
                ),
              ),
            );
        }
      },
    );
  }

  Widget _buildConversationMetaCard(
    BuildContext context,
    ThemeData theme,
    _ConversationRecord record,
  ) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final title = switch (record.eventType) {
      'session' => isZh ? '\u4f1a\u8bdd\u4fe1\u606f' : 'Session',
      'model_change' => isZh ? '\u6a21\u578b\u5207\u6362' : 'Model Change',
      'thinking_level_change' =>
        isZh ? '\u601d\u8003\u7ea7\u522b' : 'Thinking Level',
      'model_snapshot' => isZh ? '\u6a21\u578b\u5feb\u7167' : 'Model Snapshot',
      _ => isZh ? '\u4e8b\u4ef6' : 'Event',
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(110),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outline.withAlpha(35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                record.eventType == 'session'
                    ? Icons.inventory_2_outlined
                    : Icons.info_outline,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (record.timestamp != null)
                Text(
                  _formatConversationTime(record.timestamp),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (record.primary?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            SelectableText(
              record.primary!,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ],
          if (record.secondary?.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            SelectableText(
              record.secondary!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'DejaVuSansMono',
                height: 1.45,
              ),
            ),
          ],
          if (record.badge?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${record.eventType == 'session' ? (isZh ? '\u7248\u672c' : 'Version') : (isZh ? '\u503c' : 'Value')}: ${record.badge}',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConversationMessage(
    BuildContext context,
    ThemeData theme,
    _ConversationRecord record,
  ) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final isUser = record.role == 'user';
    final bubbleColor = isUser
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final textColor =
        isUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.82;
    final displayText = record.primary?.trim().isNotEmpty == true
        ? record.primary!
        : (isZh
            ? '\u672c\u6761\u6d88\u606f\u53ea\u5305\u542b\u5de5\u5177\u8c03\u7528\u3002'
            : 'This message only contains tool calls.');

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment:
                  isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                if (!isUser)
                  _buildRoleChip(context, theme, record.role ?? 'assistant'),
                if (!isUser) const SizedBox(width: 8),
                if (record.timestamp != null)
                  Text(
                    _formatConversationTime(record.timestamp),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (isUser) const SizedBox(width: 8),
                if (isUser)
                  _buildRoleChip(context, theme, record.role ?? 'user'),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 6),
                  bottomRight: Radius.circular(isUser ? 6 : 20),
                ),
              ),
              child: SelectableText(
                displayText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: textColor,
                  height: 1.55,
                ),
              ),
            ),
            if (record.toolCalls.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final toolCall in record.toolCalls) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.outline.withAlpha(35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${isZh ? '\u5de5\u5177\u8c03\u7528' : 'Tool Call'}: ${toolCall.name}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (toolCall.argumentsText.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SelectableText(
                          toolCall.argumentsText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'DejaVuSansMono',
                            height: 1.45,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (record.hasThinking)
                  _buildSmallChip(
                    theme,
                    isZh
                        ? '\u5df2\u8bb0\u5f55\u601d\u8003\u5185\u5bb9 (${record.thinkingLength ?? 0})'
                        : 'Thinking recorded (${record.thinkingLength ?? 0})',
                  ),
                if (record.provider?.isNotEmpty == true)
                  _buildSmallChip(
                    theme,
                    '${isZh ? '\u63d0\u4f9b\u5546' : 'Provider'}: ${record.provider}',
                  ),
                if (record.model?.isNotEmpty == true)
                  _buildSmallChip(
                    theme,
                    '${isZh ? '\u6a21\u578b' : 'Model'}: ${record.model}',
                  ),
                if (record.totalTokens != null)
                  _buildSmallChip(
                    theme,
                    '${isZh ? 'Tokens' : 'Tokens'}: ${record.totalTokens}',
                  ),
                if (record.stopReason?.isNotEmpty == true)
                  _buildSmallChip(
                    theme,
                    '${isZh ? '\u505c\u6b62\u539f\u56e0' : 'Stop reason'}: ${record.stopReason}',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleChip(BuildContext context, ThemeData theme, String role) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final text = switch (role) {
      'user' => isZh ? '\u7528\u6237' : 'User',
      'assistant' => isZh ? '\u52a9\u624b' : 'Assistant',
      'system' => isZh ? '\u7cfb\u7edf' : 'System',
      _ => isZh ? '\u6d88\u606f' : 'Message',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildSmallChip(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _formatConversationTime(DateTime? timestamp) {
    if (timestamp == null) return '';
    final local = timestamp.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  String _emptyStateText(AppLocalizations l10n) {
    switch (_source) {
      case _LogSource.gateway:
        return l10n.t('logsEmpty');
      case _LogSource.conversation:
        return l10n.t('logsConversationEmpty');
    }
  }

  String _jumpToLatestLabel(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    return isZh ? '跳到最新位置' : 'Jump to latest';
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

enum _ConversationRecordKind { session, event, message, raw }

class _ConversationRecord {
  const _ConversationRecord({
    required this.kind,
    required this.rawLine,
    required this.searchText,
    required this.signature,
    this.timestamp,
    this.eventType,
    this.role,
    this.primary,
    this.secondary,
    this.badge,
    this.provider,
    this.model,
    this.totalTokens,
    this.stopReason,
    this.toolCalls = const [],
    this.hasThinking = false,
    this.thinkingLength,
  });

  final _ConversationRecordKind kind;
  final String rawLine;
  final String searchText;
  final String signature;
  final DateTime? timestamp;
  final String? eventType;
  final String? role;
  final String? primary;
  final String? secondary;
  final String? badge;
  final String? provider;
  final String? model;
  final int? totalTokens;
  final String? stopReason;
  final List<_ConversationToolCall> toolCalls;
  final bool hasThinking;
  final int? thinkingLength;

  static _ConversationRecord parse(String rawLine) {
    try {
      final decoded = jsonDecode(rawLine);
      if (decoded is! Map) {
        return _raw(rawLine);
      }

      final map = Map<String, dynamic>.from(decoded);
      final type = map['type']?.toString();
      final timestamp = _parseTimestamp(map['timestamp']);

      switch (type) {
        case 'session':
          final sessionId = map['id']?.toString();
          final cwd = map['cwd']?.toString();
          final version = map['version']?.toString();
          return _ConversationRecord(
            kind: _ConversationRecordKind.session,
            rawLine: rawLine,
            searchText: [
              type,
              sessionId,
              cwd,
              version,
            ].whereType<String>().join(' '),
            signature: '$type|$sessionId|$cwd|$version',
            timestamp: timestamp,
            eventType: 'session',
            primary: sessionId,
            secondary: cwd,
            badge: version,
          );
        case 'model_change':
          final provider = map['provider']?.toString();
          final modelId = map['modelId']?.toString();
          return _ConversationRecord(
            kind: _ConversationRecordKind.event,
            rawLine: rawLine,
            searchText: [type, provider, modelId].whereType<String>().join(' '),
            signature: '$type|$provider|$modelId',
            timestamp: timestamp,
            eventType: type,
            primary: modelId,
            secondary: provider,
          );
        case 'thinking_level_change':
          final thinkingLevel = map['thinkingLevel']?.toString();
          return _ConversationRecord(
            kind: _ConversationRecordKind.event,
            rawLine: rawLine,
            searchText: [type, thinkingLevel].whereType<String>().join(' '),
            signature: '$type|$thinkingLevel',
            timestamp: timestamp,
            eventType: type,
            primary: thinkingLevel,
            badge: thinkingLevel,
          );
        case 'custom':
          final customType = map['customType']?.toString();
          final data = _asMap(map['data']);
          if (customType == 'model-snapshot') {
            final provider = data?['provider']?.toString();
            final modelId = data?['modelId']?.toString();
            return _ConversationRecord(
              kind: _ConversationRecordKind.event,
              rawLine: rawLine,
              searchText: [
                type,
                customType,
                provider,
                modelId,
              ].whereType<String>().join(' '),
              signature: '$type|$customType|$provider|$modelId',
              timestamp: timestamp,
              eventType: 'model_snapshot',
              primary: modelId,
              secondary: provider,
            );
          }
          return _ConversationRecord(
            kind: _ConversationRecordKind.event,
            rawLine: rawLine,
            searchText: [type, customType].whereType<String>().join(' '),
            signature: '$type|$customType',
            timestamp: timestamp,
            eventType: type,
            primary: customType,
          );
        case 'message':
          return _parseMessage(rawLine, map, timestamp);
        default:
          return _ConversationRecord(
            kind: _ConversationRecordKind.event,
            rawLine: rawLine,
            searchText: [type, rawLine].whereType<String>().join(' '),
            signature: '$type|$rawLine',
            timestamp: timestamp,
            eventType: type,
            primary: type,
          );
      }
    } catch (_) {
      return _raw(rawLine);
    }
  }

  static _ConversationRecord _parseMessage(
    String rawLine,
    Map<String, dynamic> map,
    DateTime? timestamp,
  ) {
    final message = _asMap(map['message']) ?? const <String, dynamic>{};
    final role = message['role']?.toString();
    final provider = message['provider']?.toString();
    final model = message['model']?.toString();
    final stopReason = message['stopReason']?.toString();
    final usage = _asMap(message['usage']);
    final totalTokens =
        _asInt(usage?['totalTokens']) ?? _asInt(usage?['total_tokens']);
    final content = message['content'];
    final textParts = <String>[];
    final searchParts = <String>[if (role != null) role];
    final toolCalls = <_ConversationToolCall>[];
    var hasThinking = false;
    var thinkingLength = 0;

    if (content is List) {
      for (final entry in content) {
        final item = _asMap(entry);
        if (item == null) continue;
        final contentType = item['type']?.toString();
        if (contentType != null) {
          searchParts.add(contentType);
        }

        if (contentType == 'thinking') {
          hasThinking = true;
          thinkingLength += (item['thinking']?.toString() ?? '').length;
          continue;
        }

        if (contentType == 'toolCall') {
          final name = item['name']?.toString() ?? 'tool';
          final argumentsText = _formatArguments(item['arguments']);
          toolCalls.add(
            _ConversationToolCall(name: name, argumentsText: argumentsText),
          );
          searchParts
            ..add(name)
            ..add(argumentsText);
          continue;
        }

        final text = item['text']?.toString();
        if (text != null && text.trim().isNotEmpty) {
          textParts.add(text.trim());
          searchParts.add(text);
        }
      }
    } else if (content is String && content.trim().isNotEmpty) {
      textParts.add(content.trim());
      searchParts.add(content);
    }

    return _ConversationRecord(
      kind: _ConversationRecordKind.message,
      rawLine: rawLine,
      searchText: [
        ...searchParts,
        if (provider != null) provider,
        if (model != null) model,
        if (stopReason != null) stopReason,
      ].join(' '),
      signature:
          'message|$role|${textParts.join('\n\n')}|${toolCalls.length}|$provider|$model|$stopReason|$totalTokens',
      timestamp: timestamp ?? _parseTimestamp(message['timestamp']),
      eventType: 'message',
      role: role,
      primary: textParts.join('\n\n'),
      provider: provider,
      model: model,
      totalTokens: totalTokens,
      stopReason: stopReason,
      toolCalls: toolCalls,
      hasThinking: hasThinking,
      thinkingLength: thinkingLength == 0 ? null : thinkingLength,
    );
  }

  static _ConversationRecord _raw(String rawLine) {
    return _ConversationRecord(
      kind: _ConversationRecordKind.raw,
      rawLine: rawLine,
      searchText: rawLine,
      signature: rawLine,
    );
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  static DateTime? _parseTimestamp(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static String _formatArguments(Object? arguments) {
    if (arguments == null) return '';
    try {
      if (arguments is String) {
        final trimmed = arguments.trim();
        if (trimmed.isEmpty) return '';
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
          return const JsonEncoder.withIndent(
            '  ',
          ).convert(jsonDecode(trimmed));
        }
        return trimmed;
      }
      return const JsonEncoder.withIndent('  ').convert(arguments);
    } catch (_) {
      return arguments.toString();
    }
  }
}

class _ConversationToolCall {
  const _ConversationToolCall({
    required this.name,
    required this.argumentsText,
  });

  final String name;
  final String argumentsText;
}
