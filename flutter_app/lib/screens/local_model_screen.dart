import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../l10n/app_localizations.dart';
import '../providers/gateway_provider.dart';
import '../services/local_model_service.dart';
import 'local_model_catalog_screen.dart';
import 'local_model_chat_screen.dart';
import 'local_model_library_screen.dart';
import 'local_model_runtime_settings_screen.dart';

class LocalModelScreen extends StatefulWidget {
  const LocalModelScreen({
    super.key,
    this.startInstallOnOpen = false,
  });

  final bool startInstallOnOpen;

  @override
  State<LocalModelScreen> createState() => _LocalModelScreenState();
}

class _LocalModelScreenState extends State<LocalModelScreen> {
  final _downloadUrlController = TextEditingController();
  final _fileNameController = TextEditingController();
  final _aliasController = TextEditingController();
  final _portController = TextEditingController();
  final _contextController = TextEditingController();
  final _installLogController = ScrollController();

  LocalModelState _state = const LocalModelState.empty();
  bool _loading = true;
  bool _busy = false;
  bool _showInstallLogs = false;
  List<String> _installLogs = const <String>[];
  LocalModelDownloadProgress? _downloadProgress;
  String? _selectedModelFileName;
  bool _fileNameManuallyEdited = false;
  String? _pendingAliasAfterDownload;

  LocalModelDownloadedModel? get _selectedModel {
    final fileName = _selectedModelFileName;
    if (fileName == null) {
      return null;
    }
    for (final model in _state.models) {
      if (model.fileName == fileName) {
        return model;
      }
    }
    return null;
  }

  String? get _activeModelFileName =>
      _state.activeConfig?.modelPath.split('/').last;

  @override
  void initState() {
    super.initState();
    _downloadUrlController.addListener(_handleDownloadUrlChanged);
    _refreshState();
    if (widget.startInstallOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runInstallIfNeeded();
      });
    }
  }

  @override
  void dispose() {
    _downloadUrlController.removeListener(_handleDownloadUrlChanged);
    _downloadUrlController.dispose();
    _fileNameController.dispose();
    _aliasController.dispose();
    _portController.dispose();
    _contextController.dispose();
    _installLogController.dispose();
    super.dispose();
  }

  void _handleDownloadUrlChanged() {
    if (_fileNameManuallyEdited) {
      return;
    }
    final suggested = LocalModelService.suggestFileNameFromUrl(
      _downloadUrlController.text,
    );
    if (suggested.isNotEmpty && _fileNameController.text != suggested) {
      _fileNameController.text = suggested;
    }
  }

  Future<void> _refreshState() async {
    try {
      final state = await LocalModelService.readState();
      if (!mounted) {
        return;
      }
      setState(() {
        _state = state;
        _loading = false;
      });
      _syncFormWithState(state);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
      _showError(error);
    }
  }

  void _syncFormWithState(LocalModelState state) {
    final activeFileName = state.activeConfig?.modelPath.split('/').last;
    final selectedStillExists = _selectedModelFileName != null &&
        state.models.any((model) => model.fileName == _selectedModelFileName);
    final nextFileName = selectedStillExists
        ? _selectedModelFileName
        : (activeFileName != null &&
                state.models.any((model) => model.fileName == activeFileName)
            ? activeFileName
            : state.models.isNotEmpty
                ? state.models.first.fileName
                : null);

    if (mounted) {
      setState(() => _selectedModelFileName = nextFileName);
    }

    final selectedModel = nextFileName == null
        ? null
        : state.models.firstWhere((model) => model.fileName == nextFileName);
    final nextAlias = state.activeConfig?.alias.isNotEmpty == true
        ? state.activeConfig!.alias
        : selectedModel?.defaultAlias ?? '';
    if (_aliasController.text.trim().isEmpty && nextAlias.isNotEmpty) {
      _aliasController.text = nextAlias;
    }

    if (_portController.text.trim().isEmpty) {
      _portController.text =
          (state.activeConfig?.port ?? LocalModelService.defaultPort)
              .toString();
    }

    if (_contextController.text.trim().isEmpty) {
      final recommendedContext = LocalModelService.recommendedContextSize(
        state.hardware,
        runtimePreferences: state.runtimePreferences,
      );
      _contextController.text =
          (state.activeConfig?.contextSize ?? recommendedContext).toString();
    }
  }

  Future<void> _runInstallIfNeeded() async {
    if (_busy || _state.installed) {
      return;
    }
    await _runInstall();
  }

  Future<void> _runInstall() async {
    if (_busy) {
      return;
    }

    setState(() {
      _busy = true;
      _showInstallLogs = true;
      _installLogs = const <String>[];
    });

    try {
      await LocalModelService.installOrUpdateLatest(
        onLogChanged: (lines) {
          if (!mounted) {
            return;
          }
          setState(() => _installLogs = lines);
          _scrollToBottom(_installLogController);
        },
      );
      await _refreshState();
    } catch (error) {
      if (mounted) {
        _showError(error);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openModelCatalog() async {
    if (_busy) {
      return;
    }

    final entry = await Navigator.of(context).push<LocalModelDownloadSelection>(
      MaterialPageRoute(
        builder: (_) => LocalModelCatalogScreen(hardware: _state.hardware),
      ),
    );
    if (!mounted || entry == null) {
      return;
    }

    _fileNameManuallyEdited = false;
    _pendingAliasAfterDownload = entry.defaultAlias;
    _downloadUrlController.text = entry.downloadUrl;
    _fileNameController.text = entry.fileName;

    await _runDownload();
  }

  Future<void> _runDownload() async {
    if (_busy) {
      return;
    }

    final l10n = context.l10n;
    final url = _downloadUrlController.text.trim();
    final fileName = LocalModelService.sanitizeModelFileName(
      _fileNameController.text,
    );
    if (url.isEmpty) {
      _showError(l10n.t('localModelErrorUrlRequired'));
      return;
    }
    if (fileName.isEmpty) {
      _showError(l10n.t('localModelErrorFileNameRequired'));
      return;
    }

    setState(() {
      _busy = true;
      _downloadProgress = null;
    });

    try {
      await LocalModelService.downloadModel(
        url: url,
        fileName: fileName,
        onProgressChanged: (progress) {
          if (!mounted) {
            return;
          }
          setState(() => _downloadProgress = progress);
        },
      );
      _downloadUrlController.clear();
      _fileNameController.clear();
      _fileNameManuallyEdited = false;
      await _refreshState();
      if (mounted) {
        setState(() => _selectedModelFileName = fileName);
        final selectedModel = _selectedModel;
        if (selectedModel != null) {
          _aliasController.text =
              _pendingAliasAfterDownload ?? selectedModel.defaultAlias;
        }
      }
      _pendingAliasAfterDownload = null;
    } catch (error) {
      _pendingAliasAfterDownload = null;
      if (mounted) {
        _showError(error);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openModelLibrary() async {
    if (_busy) {
      return;
    }

    final selectedFileName = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => LocalModelLibraryScreen(
          initialSelectedFileName: _selectedModelFileName,
        ),
      ),
    );
    if (!mounted) {
      return;
    }

    await _refreshState();
    if (selectedFileName == null) {
      return;
    }

    final matchingModel = _state.models
        .where((model) => model.fileName == selectedFileName)
        .toList(growable: false);
    if (matchingModel.isEmpty) {
      return;
    }

    setState(() => _selectedModelFileName = selectedFileName);
    _aliasController.text = matchingModel.first.defaultAlias;
  }

  Future<void> _openChatPage() async {
    final activeConfig = _state.activeConfig;
    final fallbackAlias = _aliasController.text.trim().isNotEmpty
        ? _aliasController.text.trim()
        : (_selectedModel?.defaultAlias ?? 'local-model');

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LocalModelChatScreen(
          endpointUrl: _state.endpointUrl,
          modelAlias: activeConfig?.alias ?? fallbackAlias,
          modelFileName: _activeModelFileName,
          localSessionAvailable: _state.running && activeConfig != null,
          localHardware: _state.hardware,
        ),
      ),
    );
  }

  Future<void> _openRuntimeSettings() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LocalModelRuntimeSettingsScreen(
          hardware: _state.hardware,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _refreshState();
    }
  }

  Future<void> _startServer({required bool enableProviderPreset}) async {
    if (_busy) {
      return;
    }

    final l10n = context.l10n;
    final model = _selectedModel;
    if (model == null) {
      _showError(l10n.t('localModelErrorSelectModel'));
      return;
    }

    final alias = _aliasController.text.trim().isEmpty
        ? model.defaultAlias
        : _aliasController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ??
        LocalModelService.defaultPort;
    final contextSize = int.tryParse(_contextController.text.trim()) ??
        LocalModelService.defaultContextSize;

    setState(() => _busy = true);
    try {
      await LocalModelService.start(
        model: model,
        alias: alias,
        port: port,
        contextSize: contextSize,
      );
      if (enableProviderPreset) {
        final preset = await LocalModelService.saveOrActivateProviderPreset(
          alias: alias,
          port: port,
        );
        if (!mounted) {
          return;
        }
        await context.read<GatewayProvider>().applyConfigChanges(
              source: 'local model preset ${preset.displayName}',
            );
      }
      await _refreshState();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enableProviderPreset
                  ? l10n.t(
                      'localModelPresetActivated',
                      {'model': alias},
                    )
                  : l10n.t(
                      'localModelServerStarted',
                      {'port': port},
                    ),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        _showError(error);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _stopServer() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await LocalModelService.stop();
      await _refreshState();
    } catch (error) {
      if (mounted) {
        _showError(error);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _uninstallRuntime() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await LocalModelService.uninstallRuntime();
      await _refreshState();
    } catch (error) {
      if (mounted) {
        _showError(error);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _deleteModel(LocalModelDownloadedModel model) async {
    if (_busy) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.t('localModelDeleteTitle')),
        content: Text(
          context.l10n.t(
            'localModelDeleteBody',
            {'model': model.fileName},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.t('commonCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.t('providerDetailRemoveAction')),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    setState(() => _busy = true);
    try {
      await LocalModelService.deleteModel(model);
      await _refreshState();
    } catch (error) {
      if (mounted) {
        _showError(error);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }

  void _copyText(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.t('commonCopiedToClipboard'))),
    );
  }

  void _scrollToBottom(ScrollController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) {
        return;
      }
      controller.animateTo(
        controller.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }
    final fixed = value >= 100 || unitIndex == 0 ? 0 : 1;
    return '${value.toStringAsFixed(fixed)} ${units[unitIndex]}';
  }

  String _downloadProgressText(AppLocalizations l10n) {
    final progress = _downloadProgress;
    if (progress == null) {
      return '';
    }
    if (progress.totalBytes > 0) {
      return l10n.t(
        'localModelDownloadProgressValue',
        {
          'current': _formatBytes(progress.receivedBytes),
          'total': _formatBytes(progress.totalBytes),
        },
      );
    }
    return l10n.t(
      'localModelDownloadProgressValueUnknown',
      {'current': _formatBytes(progress.receivedBytes)},
    );
  }

  String? _downloadProgressMeta(AppLocalizations l10n) {
    final progress = _downloadProgress;
    if (progress == null) {
      return null;
    }

    final parts = <String>[
      if (progress.bytesPerSecond != null)
        _formatTransferSpeed(progress.bytesPerSecond!),
      if (progress.eta != null)
        l10n.t(
          'localModelDownloadEtaLabel',
          {'value': _formatEta(progress.eta!)},
        ),
      if (progress.usingFallbackSource)
        l10n.t('localModelDownloadFallbackSource'),
    ];
    if (parts.isEmpty) {
      return null;
    }
    return parts.join(' | ');
  }

  String _formatTransferSpeed(double bytesPerSecond) {
    if (bytesPerSecond >= 1024 * 1024) {
      return '${(bytesPerSecond / 1024 / 1024).toStringAsFixed(1)} MB/s';
    }
    return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
  }

  String _formatEta(Duration duration) {
    final totalSeconds = duration.inSeconds;
    if (totalSeconds <= 0) {
      return '00:00';
    }
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _runtimePreferencesSummary(AppLocalizations l10n) {
    final prefs = _state.runtimePreferences;
    final cpuText = prefs.usesAutoCpuCores
        ? l10n.t('localModelRuntimeSettingsAuto')
        : l10n.t(
            'localModelRuntimeSettingsCpuOption',
            {'value': '${prefs.maxCpuCores}'},
          );
    final memoryText = prefs.usesAutoMemoryLimit
        ? l10n.t('localModelRuntimeSettingsAuto')
        : '${(prefs.memoryLimitMiB / 1024).toStringAsFixed(1)} GB';
    final modeText = switch (prefs.performanceMode) {
      LocalModelPerformanceMode.memorySaver =>
        l10n.t('localModelRuntimeSettingsModeMemorySaver'),
      LocalModelPerformanceMode.balanced =>
        l10n.t('localModelRuntimeSettingsModeBalanced'),
      LocalModelPerformanceMode.performance =>
        l10n.t('localModelRuntimeSettingsModePerformance'),
    };

    return [
      '${l10n.t('localModelRuntimeSettingsCpuLabel')}: $cpuText',
      '${l10n.t('localModelRuntimeSettingsMemoryLabel')}: $memoryText',
      '${l10n.t('localModelRuntimeSettingsModeTitle')}: $modeText',
    ].join(' | ');
  }

  List<_AdviceItem> _buildAdviceItems(AppLocalizations l10n) {
    final memory = _state.hardware.memoryGiB;
    final storage = _state.hardware.freeStorageGiB;
    final isChinese = l10n.locale.languageCode == 'zh';

    if (isChinese) {
      return [
        _memoryAdviceForChinese(memory),
        _storageAdviceForChinese(storage),
      ];
    }

    return [
      _memoryAdviceForEnglish(memory),
      _storageAdviceForEnglish(storage),
    ];
  }

  _AdviceItem _memoryAdviceForChinese(double memory) {
    if (memory <= 0) {
      return const _AdviceItem(
        title: '先从小模型开始',
        description: '还没读到这台手机的内存。最稳妥是先下 0.5B 或 1.5B，跑通以后再考虑 3B。',
      );
    }
    if (memory < 5) {
      return const _AdviceItem(
        title: '这台手机先别上大模型',
        description: '优先试 0.5B 或 1.5B。3B 可能会慢，4B 和 8B 暂时先不要下。',
      );
    }
    if (memory < 7) {
      return const _AdviceItem(
        title: '先试 1.5B，想更强再试 3B',
        description: '1.5B 是这档内存最稳的选择。3B 能试，但更容易发热，也更容易慢。',
      );
    }
    if (memory < 10) {
      return const _AdviceItem(
        title: '3B 最适合这台手机',
        description: '日常聊天、总结、翻译优先下 3B。想更快可留 1.5B，想更强再试 4B。',
      );
    }
    if (memory < 13) {
      return const _AdviceItem(
        title: '3B 和 4B 都比较合适',
        description: '这台手机可以把 3B 当主力，4B 当更强选项。8B 可以试，但别期望太快。',
      );
    }
    return const _AdviceItem(
      title: '可以试 8B，但不用一上来就下',
      description: '3B 和 4B 更省电也更稳。8B 适合想要更强效果，同时能接受更慢更热的情况。',
    );
  }

  _AdviceItem _storageAdviceForChinese(double storage) {
    if (storage <= 0) {
      return const _AdviceItem(
        title: '下载前尽量先留空间',
        description: '最好至少留 5GB 可用空间。模型不只是下载一次，后面还要留日志和临时文件空间。',
      );
    }
    if (storage < 3) {
      return const _AdviceItem(
        title: '剩余空间太少了',
        description: '先清空间。现在只建议下 0.5B，小模型都可能把空间吃紧。',
      );
    }
    if (storage < 6) {
      return const _AdviceItem(
        title: '空间不多，先下小模型',
        description: '优先 0.5B 或 1.5B。不要一次下太多模型，不然很快就会爆空间。',
      );
    }
    if (storage < 10) {
      return const _AdviceItem(
        title: '空间勉强够用',
        description: '3B 可以考虑，但尽量别同时留太多历史模型。想省心还是先下 1.5B 或 3B。',
      );
    }
    return const _AdviceItem(
      title: '空间基本够用',
      description: '按内存选模型就行。只是 8B 这类大模型下载更久，也更占手机空间。',
    );
  }

  _AdviceItem _memoryAdviceForEnglish(double memory) {
    if (memory <= 0) {
      return const _AdviceItem(
        title: 'Start small first',
        description:
            'Memory could not be detected. Start with 0.5B or 1.5B first, then try 3B after the basic flow works.',
      );
    }
    if (memory < 5) {
      return const _AdviceItem(
        title: 'Skip large models on this phone',
        description:
            'Try 0.5B or 1.5B first. 3B may be slow, and 4B or 8B is not a good first choice here.',
      );
    }
    if (memory < 7) {
      return const _AdviceItem(
        title: 'Start with 1.5B',
        description:
            '1.5B is the safest pick in this range. 3B may run, but it is more likely to be hot and slow.',
      );
    }
    if (memory < 10) {
      return const _AdviceItem(
        title: '3B is the safest main model',
        description:
            'Use 3B for everyday chat, summaries, and translation. Keep 1.5B for speed, or try 4B for better quality.',
      );
    }
    if (memory < 13) {
      return const _AdviceItem(
        title: '3B and 4B are both practical',
        description:
            'Use 3B as the default and 4B as the stronger option. 8B can run, but do not expect it to be fast.',
      );
    }
    return const _AdviceItem(
      title: '8B is possible, but not required',
      description:
          '3B and 4B are still the safer daily picks. 8B is for better quality when you can accept more heat and latency.',
    );
  }

  _AdviceItem _storageAdviceForEnglish(double storage) {
    if (storage <= 0) {
      return const _AdviceItem(
        title: 'Leave extra storage first',
        description:
            'Try to keep at least 5GB free. Downloads need extra room for logs and temporary files too.',
      );
    }
    if (storage < 3) {
      return const _AdviceItem(
        title: 'Storage is too tight',
        description:
            'Free up space first. Only 0.5B is realistic right now, and even that may feel tight.',
      );
    }
    if (storage < 6) {
      return const _AdviceItem(
        title: 'Use smaller models first',
        description:
            'Stick with 0.5B or 1.5B for now and avoid keeping too many old models on the phone.',
      );
    }
    if (storage < 10) {
      return const _AdviceItem(
        title: 'Storage is okay, but not generous',
        description:
            '3B is possible, but avoid storing many old models together. 1.5B or 3B is the safer choice.',
      );
    }
    return const _AdviceItem(
      title: 'Storage is mostly fine',
      description:
          'Choose by memory first. Just remember that 8B class models take longer to download and occupy much more space.',
    );
  }

  Widget _buildStatusChip(
    ThemeData theme, {
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
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
        title: Text(l10n.t('localModelTitle')),
        actions: [
          IconButton(
            tooltip: l10n.t('logsRefresh'),
            onPressed: _busy ? null : _refreshState,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildOverviewCard(theme, l10n),
                const SizedBox(height: 12),
                _buildQuickActionsCard(theme, l10n),
                const SizedBox(height: 12),
                _buildRecommendationCard(theme, l10n),
                const SizedBox(height: 12),
                _buildCatalogCard(theme, l10n),
                const SizedBox(height: 12),
                _buildRuntimeCard(theme, l10n),
                if (_showInstallLogs) ...[
                  const SizedBox(height: 12),
                  _buildLogsCard(
                    theme,
                    title: l10n.t('localModelInstallLogsTitle'),
                    lines: _installLogs,
                    controller: _installLogController,
                  ),
                ],
                const SizedBox(height: 12),
                _buildDownloadCard(theme, l10n),
                const SizedBox(height: 12),
                _buildModelsCard(theme, l10n),
                if (_state.recentLogs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildLogsCard(
                    theme,
                    title: l10n.t('localModelRuntimeLogsTitle'),
                    lines: _state.recentLogs,
                    controller: null,
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildOverviewCard(ThemeData theme, AppLocalizations l10n) {
    final statusColor = !_state.installed
        ? theme.colorScheme.outline
        : _state.running
            ? AppColors.statusGreen
            : AppColors.statusAmber;

    final memoryText = _state.hardware.memoryGiB > 0
        ? _state.hardware.memoryGiB.toStringAsFixed(1)
        : l10n.t('commonUnknown');
    final storageText = _state.hardware.freeStorageGiB > 0
        ? _state.hardware.freeStorageGiB.toStringAsFixed(1)
        : l10n.t('commonUnknown');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.t('localModelTitle'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.t('localModelIntro'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _buildStatusChip(
                  theme,
                  text: !_state.installed
                      ? l10n.t('commonNotInstalled')
                      : _state.running
                          ? l10n.t('packageCpolarStatusRunning')
                          : l10n.t('packageCpolarStatusStopped'),
                  color: statusColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatusChip(
                  theme,
                  text: l10n.t(
                    'localModelChipArch',
                    {'value': _state.architecture},
                  ),
                  color: theme.colorScheme.primary,
                ),
                _buildStatusChip(
                  theme,
                  text: l10n.t('localModelChipRam', {'value': memoryText}),
                  color: theme.colorScheme.secondary,
                ),
                _buildStatusChip(
                  theme,
                  text: l10n.t('localModelChipStorage', {'value': storageText}),
                  color: theme.colorScheme.tertiary,
                ),
              ],
            ),
            if (_state.installedVersion?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Text(
                '${l10n.t('commonVersion')}: ${_state.installedVersion}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (_state.activeConfig != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SelectableText(
                      '${l10n.t('providerDetailEndpoint')}: ${_state.endpointUrl}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'DejaVuSansMono',
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.t('commonCopy'),
                    onPressed: () => _copyText(_state.endpointUrl),
                    icon: const Icon(Icons.copy_all_rounded),
                  ),
                ],
              ),
            ],
            if (!_state.archSupported) ...[
              const SizedBox(height: 12),
              Text(
                l10n.t(
                  'localModelUnsupportedArchitecture',
                  {'arch': _state.architecture},
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationCard(ThemeData theme, AppLocalizations l10n) {
    final adviceItems = _buildAdviceItems(l10n);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('localModelRecommendationTitle'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            for (final item in adviceItems) ...[
              Text(
                item.title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsCard(ThemeData theme, AppLocalizations l10n) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('localModelQuickActionsTitle'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.t('localModelQuickActionsBody'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _openModelLibrary,
                  icon: const Icon(Icons.folder_copy_outlined),
                  label: Text(l10n.t('localModelOpenLibraryAction')),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _openChatPage,
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: Text(l10n.t('localModelOpenChatAction')),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _openRuntimeSettings,
                  icon: const Icon(Icons.tune_rounded),
                  label: Text(l10n.t('localModelOpenRuntimeSettingsAction')),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _state.running && _state.activeConfig != null
                  ? l10n.t('localModelChatAvailableHint')
                  : l10n.t('localModelChatPreopenHint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCatalogCard(ThemeData theme, AppLocalizations l10n) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('localModelCatalogBrowseTitle'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.t('localModelCatalogBrowseBody'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _openModelCatalog,
              icon: const Icon(Icons.manage_search_rounded),
              label: Text(l10n.t('localModelCatalogOpenAction')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuntimeCard(ThemeData theme, AppLocalizations l10n) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('localModelRuntimeTitle'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.t('localModelRuntimeBody'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(70),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _runtimePreferencesSummary(l10n),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!_state.installed)
                  FilledButton.icon(
                    onPressed:
                        !_busy && _state.archSupported ? _runInstall : null,
                    icon: const Icon(Icons.download_rounded),
                    label: Text(l10n.t('packagesInstall')),
                  ),
                if (_state.installed)
                  FilledButton.icon(
                    onPressed:
                        !_busy && _state.archSupported ? _runInstall : null,
                    icon: const Icon(Icons.system_update_alt),
                    label: Text(l10n.t('gatewayUpdate')),
                  ),
                if (_state.installed && !_state.running)
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _startServer(enableProviderPreset: false),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(l10n.t('localModelStartServer')),
                  ),
                if (_state.installed && _state.running)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _stopServer,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(l10n.t('packageCpolarStop')),
                  ),
                if (_state.installed)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _uninstallRuntime,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l10n.t('packagesUninstall')),
                  ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _openRuntimeSettings,
                  icon: const Icon(Icons.tune_rounded),
                  label: Text(l10n.t('localModelOpenRuntimeSettingsAction')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadCard(ThemeData theme, AppLocalizations l10n) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('localModelManualDownloadTitle'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.t('localModelManualDownloadBody'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _downloadUrlController,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: l10n.t('localModelDownloadUrlLabel'),
                hintText:
                    'https://huggingface.co/.../resolve/main/model-q4_k_m.gguf',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fileNameController,
              decoration: InputDecoration(
                labelText: l10n.t('localModelFileNameLabel'),
              ),
              onChanged: (_) {
                _fileNameManuallyEdited = true;
              },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed:
                  _busy ? null : (_state.archSupported ? _runDownload : null),
              icon: const Icon(Icons.download_for_offline_outlined),
              label: Text(l10n.t('localModelDownloadAction')),
            ),
            if (_downloadProgress != null) ...[
              const SizedBox(height: 16),
              Text(
                l10n.t('localModelDownloadProgressTitle'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: _downloadProgress!.fraction,
              ),
              const SizedBox(height: 8),
              Text(
                _downloadProgressText(l10n),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_downloadProgressMeta(l10n) case final meta?) ...[
                const SizedBox(height: 4),
                Text(
                  meta,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                l10n.t(
                  'localModelDownloadSourceLabel',
                  {'value': _downloadProgress!.sourceHost},
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModelsCard(ThemeData theme, AppLocalizations l10n) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('localModelModelsTitle'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            if (_state.models.isEmpty)
              Text(
                l10n.t('localModelNoModels'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _selectedModelFileName,
                items: [
                  for (final model in _state.models)
                    DropdownMenuItem(
                      value: model.fileName,
                      child: Text(model.fileName),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() => _selectedModelFileName = value);
                        final selectedModel = _selectedModel;
                        if (selectedModel != null) {
                          _aliasController.text = selectedModel.defaultAlias;
                        }
                      },
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _aliasController,
              decoration: InputDecoration(
                labelText: l10n.t('customProviderAlias'),
                hintText: 'qwen-3b-local',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.t('nodeGatewayPort'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contextController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.t('localModelContextSizeLabel'),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy || _state.models.isEmpty
                      ? null
                      : () => _startServer(enableProviderPreset: false),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(l10n.t('localModelStartServer')),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || _state.models.isEmpty
                      ? null
                      : () => _startServer(enableProviderPreset: true),
                  icon: const Icon(Icons.flash_on_outlined),
                  label: Text(l10n.t('localModelStartAndEnable')),
                ),
              ],
            ),
            if (_state.models.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                l10n.t('localModelStoredModelsTitle'),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              for (final model in _state.models)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  selected: model.fileName == _selectedModelFileName,
                  title: Text(model.fileName),
                  subtitle: Text(
                    '${_formatBytes(model.sizeBytes)} · ${model.modifiedAt.toLocal()}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _busy ? null : () => _deleteModel(model),
                  ),
                  onTap: _busy
                      ? null
                      : () {
                          setState(
                            () => _selectedModelFileName = model.fileName,
                          );
                          _aliasController.text = model.defaultAlias;
                        },
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLogsCard(
    ThemeData theme, {
    required String title,
    required List<String> lines,
    required ScrollController? controller,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: controller == null
                  ? SingleChildScrollView(
                      child: SelectableText(
                        lines.join('\n'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'DejaVuSansMono',
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    )
                  : Scrollbar(
                      controller: controller,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: controller,
                        child: SelectableText(
                          lines.join('\n'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'DejaVuSansMono',
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdviceItem {
  const _AdviceItem({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;
}
