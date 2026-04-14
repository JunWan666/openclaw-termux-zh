import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../l10n/app_localizations.dart';
import '../models/custom_provider_preset.dart';
import '../services/local_model_chat_service.dart';
import '../services/local_model_service.dart';
import 'local_model_chat_settings_screen.dart';

class LocalModelChatScreen extends StatefulWidget {
  const LocalModelChatScreen({
    super.key,
    required this.endpointUrl,
    required this.modelAlias,
    required this.localSessionAvailable,
    required this.localHardware,
    this.modelFileName,
  });

  final String endpointUrl;
  final String modelAlias;
  final bool localSessionAvailable;
  final LocalModelHardwareProfile localHardware;
  final String? modelFileName;

  @override
  State<LocalModelChatScreen> createState() => _LocalModelChatScreenState();
}

class _LocalModelChatScreenState extends State<LocalModelChatScreen> {
  static const _benchmarkPrompt =
      '请直接输出从 1 到 180 的数字，每个数字之间用一个空格隔开，不要解释，不要换行，不要加标题。';

  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _chatService = LocalModelChatService();

  late final LocalModelChatSessionConfig _localSession;
  late LocalModelChatSessionConfig _session;
  List<_LocalChatMessage> _messages = const <_LocalChatMessage>[];
  bool _sending = false;
  bool _benchmarking = false;
  bool _streamOutput = true;
  bool _thinkingEnabled = true;
  bool _showReasoning = true;
  bool _headerExpanded = false;
  bool _localSessionReady = false;
  LocalModelChatMetrics? _lastBenchmarkMetrics;
  LocalModelRuntimeSample? _previousRuntimeSample;
  LocalModelRuntimeUsage? _runtimeUsage;
  bool _runtimeEndpointReachable = false;
  int _runtimeSampleMisses = 0;
  Timer? _runtimeTimer;
  bool _pollingRuntime = false;

  @override
  void initState() {
    super.initState();
    _localSessionReady = widget.localSessionAvailable;
    _localSession = LocalModelChatSessionConfig(
      source: LocalModelChatSessionSource.local,
      displayName: widget.modelAlias,
      endpointUrl: widget.endpointUrl,
      modelId: widget.modelAlias,
      compatibility: CustomProviderCompatibility.openaiChatCompletions,
      modelFileName: widget.modelFileName,
      providerId: LocalModelService.localProviderId,
      sourceLabel: '',
    );
    _session = _localSession;
    _startRuntimePolling();
  }

  @override
  void dispose() {
    _runtimeTimer?.cancel();
    _chatService.cancelActiveRequest();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isUsingLocalSession =>
      _session.source == LocalModelChatSessionSource.local;

  bool get _composerEnabled =>
      !_sending && (!_isUsingLocalSession || _localSessionReady);

  void _startRuntimePolling() {
    _refreshRuntimeUsage();
    _runtimeTimer?.cancel();
    _runtimeTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshRuntimeUsage(),
    );
  }

  Future<void> _refreshRuntimeUsage() async {
    if (_pollingRuntime) {
      return;
    }

    _pollingRuntime = true;
    try {
      final endpointUri = Uri.tryParse(_session.endpointUrl);
      final endpointPort = endpointUri?.hasPort == true
          ? endpointUri!.port
          : LocalModelService.defaultPort;
      final sample = await LocalModelService.readRuntimeSample();
      final endpointReachable = _isUsingLocalSession
          ? await LocalModelService.isEndpointReachableForPort(endpointPort)
          : false;
      if (!mounted) {
        return;
      }

      final usage = sample == null
          ? null
          : LocalModelService.computeRuntimeUsage(
              sample: sample,
              previousSample: _previousRuntimeSample,
              hardware: widget.localHardware,
            );

      setState(() {
        if (sample != null) {
          _previousRuntimeSample = sample;
          _runtimeUsage = usage;
          _runtimeSampleMisses = 0;
        } else if (!endpointReachable) {
          _previousRuntimeSample = null;
          _runtimeUsage = null;
          _runtimeSampleMisses = 0;
        } else {
          _runtimeSampleMisses += 1;
        }
        _runtimeEndpointReachable = endpointReachable;
        _localSessionReady = sample != null || endpointReachable;
      });
    } finally {
      _pollingRuntime = false;
    }
  }

  Future<void> _sendMessage() async {
    if (_sending) {
      return;
    }

    final l10n = context.l10n;
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      _showSnack(l10n.t('localModelChatErrorEmpty'));
      return;
    }

    final nextUserMessage = _LocalChatMessage(
      id: _nextMessageId(),
      role: _LocalChatRole.user,
      content: text,
      requestContent: text,
      timestamp: DateTime.now(),
    );
    final assistantMessageId = _nextMessageId();
    final requestMessages = <Map<String, String>>[
      for (final message in _messages)
        if (!message.isError && message.requestContent.trim().isNotEmpty)
          message.toRequestJson(),
      nextUserMessage.toRequestJson(),
    ];

    _inputController.clear();
    setState(() {
      if (_messages.isEmpty) {
        _headerExpanded = false;
      }
      _messages = [
        ..._messages,
        nextUserMessage,
        _LocalChatMessage(
          id: assistantMessageId,
          role: _LocalChatRole.assistant,
          content: '',
          reasoning: '',
          requestContent: '',
          timestamp: DateTime.now(),
          isStreaming: true,
        ),
      ];
      _sending = true;
    });
    _scrollToBottom();

    try {
      if (_streamOutput) {
        await for (final event in _chatService.streamReply(
          baseUrl: _session.endpointUrl,
          modelId: _session.modelId,
          messages: requestMessages,
          apiKey: _session.apiKey,
          compatibility: _session.compatibility,
          enableThinking: _thinkingEnabled,
        )) {
          if (!mounted) {
            return;
          }
          _updateAssistantMessage(
            assistantMessageId,
            content: event.content,
            reasoning: event.reasoning,
            requestContent: event.content,
            isStreaming: !event.done,
            metrics: event.metrics,
          );
        }
      } else {
        final reply = await _chatService.createReply(
          baseUrl: _session.endpointUrl,
          modelId: _session.modelId,
          messages: requestMessages,
          apiKey: _session.apiKey,
          compatibility: _session.compatibility,
          enableThinking: _thinkingEnabled,
        );
        if (!mounted) {
          return;
        }
        _updateAssistantMessage(
          assistantMessageId,
          content: reply.content,
          reasoning: reply.reasoning,
          requestContent: reply.content,
          isStreaming: false,
          metrics: reply.metrics,
        );
      }
    } on LocalModelChatCancelledException {
      if (!mounted) {
        return;
      }
      final current = _messageById(assistantMessageId);
      if (current == null) {
        return;
      }
      if (current.content.trim().isEmpty && current.reasoning.trim().isEmpty) {
        _removeMessageById(assistantMessageId);
      } else {
        _updateAssistantMessage(
          assistantMessageId,
          content: current.content,
          reasoning: current.reasoning,
          requestContent: current.content,
          isStreaming: false,
          wasStopped: true,
        );
      }
      _showSnack(l10n.t('localModelChatStopped'));
    } catch (error) {
      if (!mounted) {
        return;
      }
      final existing = _messageById(assistantMessageId);
      if (existing == null ||
          (existing.content.trim().isEmpty &&
              existing.reasoning.trim().isEmpty)) {
        _updateAssistantMessage(
          assistantMessageId,
          content: l10n.t(
            'localModelChatRequestFailed',
            {'error': '$error'},
          ),
          requestContent: '',
          isStreaming: false,
          isError: true,
        );
      } else {
        setState(() {
          _messages = [
            ..._messages,
            _LocalChatMessage(
              id: _nextMessageId(),
              role: _LocalChatRole.assistant,
              content: l10n.t(
                'localModelChatRequestFailed',
                {'error': '$error'},
              ),
              requestContent: '',
              timestamp: DateTime.now(),
              isError: true,
            ),
          ];
        });
      }
      _scrollToBottom();
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  // ignore: unused_element
  Future<void> _runBenchmark() async {
    if (_sending || _benchmarking) {
      return;
    }

    if (_isUsingLocalSession && !_localSessionReady) {
      _showSnack(context.l10n.t('localModelChatLocalUnavailableHint'));
      return;
    }

    setState(() => _benchmarking = true);
    try {
      // Warm up once so benchmark results are closer to sustained output speed.
      await _chatService.createReply(
        baseUrl: _session.endpointUrl,
        modelId: _session.modelId,
        messages: const [
          {
            'role': 'user',
            'content': '只回复 1。',
          },
        ],
        apiKey: _session.apiKey,
        compatibility: _session.compatibility,
        enableThinking: false,
        maxTokens: 8,
        temperature: 0,
      );

      final result = await _chatService.createReply(
        baseUrl: _session.endpointUrl,
        modelId: _session.modelId,
        messages: const [
          {
            'role': 'user',
            'content': _benchmarkPrompt,
          },
        ],
        apiKey: _session.apiKey,
        compatibility: _session.compatibility,
        enableThinking: false,
        maxTokens: 256,
        temperature: 0,
      );
      if (!mounted) {
        return;
      }
      setState(() => _lastBenchmarkMetrics = result.metrics);
      _showSnack(context.l10n.t('localModelChatBenchmarkDone'));
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack(
        context.l10n.t(
          'localModelChatBenchmarkFailed',
          {'error': '$error'},
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _benchmarking = false);
      }
    }
  }

  void _stopMessageGeneration() {
    if (!_sending) {
      return;
    }
    _chatService.cancelActiveRequest();
  }

  Future<void> _openSettingsPage() async {
    final result =
        await Navigator.of(context).push<LocalModelChatSettingsResult>(
      MaterialPageRoute(
        builder: (_) => LocalModelChatSettingsScreen(
          localSession: _localSession,
          currentSession: _session,
          streamOutput: _streamOutput,
          thinkingEnabled: _thinkingEnabled,
          showReasoning: _showReasoning,
          headerExpanded: _headerExpanded,
        ),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    final sessionChanged = !_session.sameTarget(result.session);
    setState(() {
      _session = result.session;
      _streamOutput = result.streamOutput;
      _thinkingEnabled = result.thinkingEnabled;
      _showReasoning = result.showReasoning;
      _headerExpanded = result.headerExpanded;
      if (sessionChanged) {
        _messages = const <_LocalChatMessage>[];
        _lastBenchmarkMetrics = null;
      }
    });

    if (sessionChanged) {
      _showSnack(context.l10n.t('localModelChatSessionChanged'));
    }
  }

  Future<void> _clearConversation() async {
    if (_messages.isEmpty && !_sending) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.t('localModelChatClearTitle')),
        content: Text(context.l10n.t('localModelChatClearBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.t('commonCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.t('commonDone')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _messages = const <_LocalChatMessage>[]);
  }

  _LocalChatMessage? _messageById(String id) {
    for (final message in _messages) {
      if (message.id == id) {
        return message;
      }
    }
    return null;
  }

  void _removeMessageById(String id) {
    setState(() {
      _messages = _messages.where((message) => message.id != id).toList();
    });
  }

  void _updateAssistantMessage(
    String messageId, {
    String? content,
    String? reasoning,
    String? requestContent,
    bool? isStreaming,
    bool? isError,
    bool? wasStopped,
    LocalModelChatMetrics? metrics,
  }) {
    setState(() {
      _messages = [
        for (final message in _messages)
          if (message.id == messageId)
            message.copyWith(
              content: content,
              reasoning: reasoning,
              requestContent: requestContent,
              isStreaming: isStreaming,
              isError: isError,
              wasStopped: wasStopped,
              metrics: metrics,
            )
          else
            message,
      ];
    });
    _scrollToBottom();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  String _nextMessageId() => DateTime.now().microsecondsSinceEpoch.toString();

  String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatDuration(Duration duration) {
    final seconds = duration.inMilliseconds / 1000;
    if (seconds >= 10) {
      return '${seconds.toStringAsFixed(1)}s';
    }
    return '${seconds.toStringAsFixed(2)}s';
  }

  String _formatMemoryMiB(double value) {
    if (value >= 1024) {
      return '${(value / 1024).toStringAsFixed(2)} GB';
    }
    return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} MB';
  }

  String _formatMemoryGiB(double value) {
    return '${value.toStringAsFixed(1)} GB';
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    _showSnack(context.l10n.t('commonCopiedToClipboard'));
  }

  Widget _buildRuntimeChip(
    ThemeData theme, {
    required IconData icon,
    required String text,
    required Color color,
    bool compact = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 12 : 14, color: color),
          SizedBox(width: compact ? 4 : 6),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCopyableEndpoint(ThemeData theme, AppLocalizations l10n) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SelectableText(
            '${l10n.t('providerDetailEndpoint')}: ${_session.endpointUrl}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'DejaVuSansMono',
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: l10n.t('commonCopy'),
          onPressed: () => _copyText(_session.endpointUrl),
          icon: const Icon(Icons.copy_all_rounded),
        ),
      ],
    );
  }

  Widget _buildRuntimeMemoryPanel(
    ThemeData theme,
    AppLocalizations l10n,
    LocalModelRuntimeUsage usage,
  ) {
    final totalMemoryGiB = widget.localHardware.memoryGiB;
    final totalMemoryMiB = totalMemoryGiB > 0 ? totalMemoryGiB * 1024 : 0.0;
    final usageRatio = totalMemoryMiB > 0
        ? (usage.rssMiB / totalMemoryMiB).clamp(0.0, 1.0)
        : null;
    final memorySummary = totalMemoryGiB > 0
        ? l10n.t(
            'localModelChatRuntimeMemoryUsage',
            {
              'used': _formatMemoryMiB(usage.rssMiB),
              'total': _formatMemoryGiB(totalMemoryGiB),
            },
          )
        : l10n.t(
            'localModelChatRuntimeMemory',
            {'value': _formatMemoryMiB(usage.rssMiB)},
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(92),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.storage_rounded,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.t('localModelChatRuntimeMemoryPanelTitle'),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                l10n.t('localModelChatRuntimeRefreshing'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: usageRatio,
              backgroundColor:
                  theme.colorScheme.surfaceContainerHighest.withAlpha(60),
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            memorySummary,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.t(
              'localModelChatRuntimeThreads',
              {'value': '${usage.threadCount}'},
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuntimeStatusWrap(ThemeData theme, AppLocalizations l10n) {
    final usage = _runtimeUsage;
    if (!_localSessionReady) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildRuntimeChip(
            theme,
            icon: Icons.power_settings_new_rounded,
            text: l10n.t('localModelChatRuntimeNotRunning'),
            color: theme.colorScheme.error,
          ),
        ],
      );
    }

    if (usage == null) {
      if (_runtimeEndpointReachable && _runtimeSampleMisses >= 3) {
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildRuntimeChip(
              theme,
              icon: Icons.check_circle_rounded,
              text: l10n.t('localModelChatRuntimeConnected'),
              color: Colors.green,
            ),
            _buildRuntimeChip(
              theme,
              icon: Icons.info_outline_rounded,
              text: l10n.t('localModelChatRuntimeUnavailable'),
              color: theme.colorScheme.secondary,
            ),
          ],
        );
      }

      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _buildRuntimeChip(
            theme,
            icon: Icons.hourglass_bottom_rounded,
            text: l10n.t('localModelChatRuntimeWaiting'),
            color: theme.colorScheme.primary,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildRuntimeChip(
          theme,
          icon: Icons.check_circle_rounded,
          text: l10n.t('localModelChatRuntimeConnected'),
          color: Colors.green,
        ),
        const SizedBox(height: 10),
        _buildRuntimeMemoryPanel(theme, l10n, usage),
      ],
    );
  }

  String _compactRuntimeStatusText(AppLocalizations l10n) {
    if (!_isUsingLocalSession) {
      return _session.sourceLabel.trim().isNotEmpty
          ? _session.sourceLabel
          : l10n.t('localModelChatSavedConfigSource');
    }
    if (!_localSessionReady) {
      return l10n.t('localModelChatRuntimeNotRunning');
    }
    if (_runtimeUsage != null || _runtimeEndpointReachable) {
      return l10n.t('localModelChatRuntimeConnected');
    }
    return l10n.t('localModelChatRuntimeWaiting');
  }

  IconData _compactRuntimeStatusIcon() {
    if (!_isUsingLocalSession) {
      return Icons.cloud_done_rounded;
    }
    if (!_localSessionReady) {
      return Icons.power_settings_new_rounded;
    }
    if (_runtimeUsage != null || _runtimeEndpointReachable) {
      return Icons.check_circle_rounded;
    }
    return Icons.hourglass_bottom_rounded;
  }

  Color _compactRuntimeStatusColor(ThemeData theme) {
    if (!_isUsingLocalSession) {
      return theme.colorScheme.primary;
    }
    if (!_localSessionReady) {
      return theme.colorScheme.error;
    }
    if (_runtimeUsage != null || _runtimeEndpointReachable) {
      return Colors.green;
    }
    return theme.colorScheme.primary;
  }

  String? _compactMemorySummary(AppLocalizations l10n) {
    if (!_isUsingLocalSession) {
      return null;
    }

    final usage = _runtimeUsage;
    if (usage != null) {
      final totalMemoryGiB = widget.localHardware.memoryGiB;
      if (totalMemoryGiB > 0) {
        return l10n.t(
          'localModelChatRuntimeMemoryUsage',
          {
            'used': _formatMemoryMiB(usage.rssMiB),
            'total': _formatMemoryGiB(totalMemoryGiB),
          },
        );
      }
      return l10n.t(
        'localModelChatRuntimeMemory',
        {'value': _formatMemoryMiB(usage.rssMiB)},
      );
    }

    if (_runtimeEndpointReachable && _runtimeSampleMisses >= 3) {
      return l10n.t('localModelChatRuntimeUnavailable');
    }
    if (_localSessionReady || _runtimeEndpointReachable) {
      return l10n.t('localModelChatRuntimeWaiting');
    }
    return null;
  }

  Widget _buildCollapsedHeaderSummary(ThemeData theme, AppLocalizations l10n) {
    final memorySummary = _compactMemorySummary(l10n);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildRuntimeChip(
          theme,
          icon: _compactRuntimeStatusIcon(),
          text: _compactRuntimeStatusText(l10n),
          color: _compactRuntimeStatusColor(theme),
          compact: true,
        ),
        if (memorySummary != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Icon(
                  Icons.storage_rounded,
                  size: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    memorySummary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String? _benchmarkSummary(AppLocalizations l10n) {
    final metrics = _lastBenchmarkMetrics;
    if (metrics == null) {
      return null;
    }

    final parts = <String>[
      l10n.t(
        'localModelChatMetricDuration',
        {'value': _formatDuration(metrics.totalDuration)},
      ),
      if (metrics.firstTokenLatency != null)
        l10n.t(
          'localModelChatMetricFirstToken',
          {'value': _formatDuration(metrics.firstTokenLatency!)},
        ),
      if (metrics.tokensPerSecond != null)
        l10n.t(
          'localModelChatMetricTokensPerSecond',
          {'value': metrics.tokensPerSecond!.toStringAsFixed(1)},
        ),
      if (metrics.completionTokens != null)
        l10n.t(
          metrics.completionTokensEstimated
              ? 'localModelChatMetricOutputTokensEstimated'
              : 'localModelChatMetricOutputTokens',
          {'value': '${metrics.completionTokens}'},
        ),
    ];

    return parts.join(' · ');
  }

  String _settingsSummary(AppLocalizations l10n) {
    final values = <String>[
      _streamOutput
          ? l10n.t('localModelChatSettingStateStreamOn')
          : l10n.t('localModelChatSettingStateStreamOff'),
      _thinkingEnabled
          ? l10n.t('localModelChatSettingStateThinkingOn')
          : l10n.t('localModelChatSettingStateThinkingOff'),
      _showReasoning
          ? l10n.t('localModelChatSettingStateReasoningOn')
          : l10n.t('localModelChatSettingStateReasoningOff'),
    ];
    return values.join(' · ');
  }

  String _reasoningPreview(String reasoning) {
    return reasoning.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  MarkdownStyleSheet _markdownStyleSheet(ThemeData theme,
      {required bool subtle}) {
    final baseColor = subtle
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurface;
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyMedium?.copyWith(
        color: baseColor,
        height: 1.55,
      ),
      code: theme.textTheme.bodySmall?.copyWith(
        fontFamily: 'DejaVuSansMono',
        fontSize: 12,
        color: baseColor,
      ),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(90),
        borderRadius: BorderRadius.circular(14),
      ),
      blockquoteDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: theme.colorScheme.primary, width: 4),
        ),
      ),
      listBullet: theme.textTheme.bodyMedium?.copyWith(
        color: baseColor,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildHeaderCard(ThemeData theme, AppLocalizations l10n) {
    final benchmarkSummary = _benchmarkSummary(l10n);
    final showLocalRuntime = _isUsingLocalSession;
    final compactModelName = (_session.modelFileName ?? '').trim().isNotEmpty
        ? _session.modelFileName!
        : _session.displayName;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              14,
              _headerExpanded ? 16 : 10,
              14,
              _headerExpanded ? 16 : 10,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        compactModelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: (_headerExpanded
                                ? theme.textTheme.titleSmall
                                : theme.textTheme.labelLarge)
                            ?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: _headerExpanded
                          ? l10n.t('localModelChatHeaderCollapseAction')
                          : l10n.t('localModelChatHeaderExpandAction'),
                      onPressed: () {
                        setState(() => _headerExpanded = !_headerExpanded);
                      },
                      icon: Icon(
                        _headerExpanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                      ),
                    ),
                  ],
                ),
                if (_headerExpanded) ...[
                  const SizedBox(height: 4),
                  Text(
                    _settingsSummary(l10n),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  if (showLocalRuntime) ...[
                    const SizedBox(height: 10),
                    _buildRuntimeStatusWrap(theme, l10n),
                  ],
                  if (showLocalRuntime && !_localSessionReady) ...[
                    const SizedBox(height: 12),
                    Text(
                      l10n.t('localModelChatLocalUnavailableHint'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                        height: 1.45,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    l10n.t('localModelChatIntro'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${l10n.t('localModelChatModelLabel')}: ${_session.modelId}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if ((_session.modelFileName ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _session.modelFileName!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (_session.sourceLabel.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${l10n.t('localModelChatSessionSourceTitle')}: ${_session.sourceLabel}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  _buildCopyableEndpoint(theme, l10n),
                  const SizedBox(height: 10),
                  Text(
                    l10n.t('localModelChatHeaderHint'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  if (benchmarkSummary != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withAlpha(80),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.t('localModelChatBenchmarkTitle'),
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            benchmarkSummary,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ] else ...[
                  const SizedBox(height: 8),
                  _buildCollapsedHeaderSummary(theme, l10n),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('localModelChatTitle')),
        actions: [
          IconButton(
            tooltip: l10n.t('localModelChatSettingsAction'),
            onPressed: _sending ? null : _openSettingsPage,
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            tooltip: l10n.t('localModelChatClearAction'),
            onPressed: _clearConversation,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeaderCard(theme, l10n),
          Expanded(
            child: _messages.isEmpty && !_sending
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.t('localModelChatEmpty'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.6,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessageBubble(theme, l10n, _messages[index]);
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!_composerEnabled && _isUsingLocalSession) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              l10n.t('localModelChatLocalUnavailableHint'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                        TextField(
                          controller: _inputController,
                          minLines: 1,
                          maxLines: 6,
                          enabled: _composerEnabled,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) {
                            if (_composerEnabled) {
                              _sendMessage();
                            }
                          },
                          decoration: InputDecoration(
                            hintText: _isUsingLocalSession &&
                                    !_localSessionReady
                                ? l10n.t('localModelChatComposerDisabledHint')
                                : l10n.t('localModelChatComposerHint'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (_sending)
                    OutlinedButton(
                      onPressed: _stopMessageGeneration,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(56, 56),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Icon(Icons.stop_rounded),
                    )
                  else
                    FilledButton(
                      onPressed: _composerEnabled ? _sendMessage : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(56, 56),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Icon(Icons.send_rounded),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
    ThemeData theme,
    AppLocalizations l10n,
    _LocalChatMessage message,
  ) {
    final reasoningPreview = _reasoningPreview(message.reasoning);
    final isUser = message.role == _LocalChatRole.user;
    final backgroundColor = message.isError
        ? AppColors.statusRed.withAlpha(18)
        : isUser
            ? AppColors.accent.withAlpha(22)
            : theme.colorScheme.surfaceContainerHighest;
    final textColor =
        message.isError ? theme.colorScheme.error : theme.colorScheme.onSurface;
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isUser ? 18 : 6),
      bottomRight: Radius.circular(isUser ? 6 : 18),
    );

    final metricParts = <String>[
      _formatTimestamp(message.timestamp),
      if (message.metrics != null)
        l10n.t(
          'localModelChatMetricDuration',
          {'value': _formatDuration(message.metrics!.totalDuration)},
        ),
      if (message.metrics?.firstTokenLatency != null)
        l10n.t(
          'localModelChatMetricFirstToken',
          {'value': _formatDuration(message.metrics!.firstTokenLatency!)},
        ),
      if (message.metrics?.tokensPerSecond != null)
        l10n.t(
          'localModelChatMetricTokensPerSecond',
          {'value': message.metrics!.tokensPerSecond!.toStringAsFixed(1)},
        ),
      if (message.metrics?.completionTokens != null)
        l10n.t(
          message.metrics!.completionTokensEstimated
              ? 'localModelChatMetricOutputTokensEstimated'
              : 'localModelChatMetricOutputTokens',
          {'value': '${message.metrics!.completionTokens}'},
        ),
      if (message.wasStopped) l10n.t('localModelChatStoppedTag'),
      if (message.isStreaming) l10n.t('localModelChatSending'),
    ];

    return Align(
      alignment: alignment,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: radius,
          border: message.isError
              ? Border.all(color: AppColors.statusRed.withAlpha(80))
              : null,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isUser &&
                _showReasoning &&
                message.reasoning.trim().isNotEmpty &&
                !message.isError)
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Text(
                    l10n.t('localModelChatReasoningLabel'),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  subtitle: reasoningPreview.isEmpty
                      ? null
                      : Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            reasoningPreview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ),
                  children: [
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withAlpha(80),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: MarkdownBody(
                        data: message.reasoning,
                        selectable: true,
                        styleSheet: _markdownStyleSheet(theme, subtle: true),
                      ),
                    ),
                  ],
                ),
              ),
            if (message.content.trim().isNotEmpty)
              isUser || message.isError
                  ? SelectableText(
                      message.content,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: textColor,
                        height: 1.5,
                      ),
                    )
                  : MarkdownBody(
                      data: message.content,
                      selectable: true,
                      styleSheet: _markdownStyleSheet(theme, subtle: false),
                    )
            else if (message.isStreaming)
              Text(
                l10n.t('localModelChatSending'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              metricParts.join(' · '),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _LocalChatRole {
  user,
  assistant,
}

class _LocalChatMessage {
  const _LocalChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.requestContent,
    required this.timestamp,
    this.reasoning = '',
    this.isError = false,
    this.isStreaming = false,
    this.wasStopped = false,
    this.metrics,
  });

  final String id;
  final _LocalChatRole role;
  final String content;
  final String reasoning;
  final String requestContent;
  final DateTime timestamp;
  final bool isError;
  final bool isStreaming;
  final bool wasStopped;
  final LocalModelChatMetrics? metrics;

  _LocalChatMessage copyWith({
    String? content,
    String? reasoning,
    String? requestContent,
    bool? isError,
    bool? isStreaming,
    bool? wasStopped,
    LocalModelChatMetrics? metrics,
  }) {
    return _LocalChatMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      reasoning: reasoning ?? this.reasoning,
      requestContent: requestContent ?? this.requestContent,
      timestamp: timestamp,
      isError: isError ?? this.isError,
      isStreaming: isStreaming ?? this.isStreaming,
      wasStopped: wasStopped ?? this.wasStopped,
      metrics: metrics ?? this.metrics,
    );
  }

  Map<String, String> toRequestJson() => {
        'role': role == _LocalChatRole.user ? 'user' : 'assistant',
        'content': requestContent,
      };
}
