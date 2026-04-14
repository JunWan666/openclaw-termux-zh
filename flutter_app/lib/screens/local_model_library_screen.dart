import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../l10n/app_localizations.dart';
import '../providers/gateway_provider.dart';
import '../services/local_model_service.dart';
import 'local_model_chat_screen.dart';

class LocalModelLibraryScreen extends StatefulWidget {
  const LocalModelLibraryScreen({
    super.key,
    this.initialSelectedFileName,
  });

  final String? initialSelectedFileName;

  @override
  State<LocalModelLibraryScreen> createState() =>
      _LocalModelLibraryScreenState();
}

class _LocalModelLibraryScreenState extends State<LocalModelLibraryScreen> {
  LocalModelState _state = const LocalModelState.empty();
  bool _loading = true;
  bool _busy = false;
  String? _selectedFileName;

  String? get _activeFileName => _state.activeConfig?.modelPath.split('/').last;

  LocalModelDownloadedModel? get _selectedModel {
    final selectedFileName = _selectedFileName;
    if (selectedFileName == null) {
      return null;
    }
    for (final model in _state.models) {
      if (model.fileName == selectedFileName) {
        return model;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _selectedFileName = widget.initialSelectedFileName;
    _refreshState();
  }

  Future<void> _refreshState() async {
    try {
      final state = await LocalModelService.readState();
      if (!mounted) {
        return;
      }

      final selectedStillExists = _selectedFileName != null &&
          state.models.any((model) => model.fileName == _selectedFileName);
      final nextSelected = selectedStillExists
          ? _selectedFileName
          : state.models.isNotEmpty
              ? state.models.first.fileName
              : null;

      setState(() {
        _state = state;
        _loading = false;
        _selectedFileName = nextSelected;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
      _showError(error);
    }
  }

  Future<void> _startSelectedModel({required bool enableProviderPreset}) async {
    final model = _selectedModel;
    if (model == null || _busy) {
      return;
    }

    setState(() => _busy = true);
    try {
      final alias = _aliasForModel(model);
      final port = _state.activeConfig?.port ?? LocalModelService.defaultPort;
      final contextSize = _state.activeConfig?.contextSize ??
          LocalModelService.recommendedContextSize(
            _state.hardware,
            runtimePreferences: _state.runtimePreferences,
          );

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
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enableProviderPreset
                ? context.l10n.t(
                    'localModelPresetActivated',
                    {'model': alias},
                  )
                : context.l10n.t(
                    'localModelServerStarted',
                    {'port': port},
                  ),
          ),
        ),
      );
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

  Future<void> _openChat() async {
    final activeConfig = _state.activeConfig;
    final fallbackAlias = _selectedModel?.defaultAlias ?? 'local-model';

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LocalModelChatScreen(
          endpointUrl: _state.endpointUrl,
          modelAlias: activeConfig?.alias ?? fallbackAlias,
          modelFileName: _activeFileName ?? _selectedModel?.fileName,
          localSessionAvailable: _state.running && activeConfig != null,
          localHardware: _state.hardware,
        ),
      ),
    );
  }

  String _aliasForModel(LocalModelDownloadedModel model) {
    final activeConfig = _state.activeConfig;
    if (activeConfig != null &&
        _activeFileName == model.fileName &&
        activeConfig.alias.trim().isNotEmpty) {
      return activeConfig.alias.trim();
    }
    return model.defaultAlias;
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('localModelLibraryTitle')),
        actions: [
          IconButton(
            tooltip: l10n.t('logsRefresh'),
            onPressed: _busy ? null : _refreshState,
            icon: const Icon(Icons.refresh),
          ),
          TextButton(
            onPressed: _selectedFileName == null
                ? null
                : () => Navigator.of(context).pop(_selectedFileName),
            child: Text(l10n.t('localModelLibraryUseSelected')),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.t('localModelLibraryIntro'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                        if (_state.activeConfig != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            '${l10n.t('customProviderAlias')}: ${_state.activeConfig!.alias}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: SelectableText(
                                  '${l10n.t('providerDetailEndpoint')}: ${_state.endpointUrl}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontFamily: 'DejaVuSansMono',
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
                        if (_state.running) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildStatusChip(
                                theme,
                                text: l10n.t('localModelLibraryRunning'),
                                color: AppColors.statusGreen,
                              ),
                              OutlinedButton.icon(
                                onPressed: _busy ? null : _stopServer,
                                icon: const Icon(Icons.stop_circle_outlined),
                                label: Text(l10n.t('packageCpolarStop')),
                              ),
                              OutlinedButton.icon(
                                onPressed: _busy ? null : _openChat,
                                icon: const Icon(Icons.chat_bubble_outline),
                                label: Text(l10n.t('localModelOpenChatAction')),
                              ),
                            ],
                          ),
                        ],
                        if (!_state.running && _selectedModel != null) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _openChat,
                            icon: const Icon(Icons.chat_bubble_outline),
                            label: Text(l10n.t('localModelOpenChatAction')),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_state.models.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l10n.t('localModelLibraryEmpty'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                else
                  for (final model in _state.models)
                    _buildModelCard(theme, l10n, model),
              ],
            ),
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

  Widget _buildModelCard(
    ThemeData theme,
    AppLocalizations l10n,
    LocalModelDownloadedModel model,
  ) {
    final isSelected = model.fileName == _selectedFileName;
    final isActive = model.fileName == _activeFileName;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: _busy
            ? null
            : () {
                setState(() => _selectedFileName = model.fileName);
              },
        borderRadius: BorderRadius.circular(12),
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
                          model.fileName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_formatBytes(model.sizeBytes)} • ${model.modifiedAt.toLocal()}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${l10n.t('customProviderAlias')}: ${_aliasForModel(model)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (isSelected)
                    _buildStatusChip(
                      theme,
                      text: l10n.t('localModelLibrarySelected'),
                      color: theme.colorScheme.primary,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (isActive)
                    _buildStatusChip(
                      theme,
                      text: _state.running
                          ? l10n.t('localModelLibraryRunning')
                          : l10n.t('localModelLibraryConfigured'),
                      color: _state.running
                          ? AppColors.statusGreen
                          : AppColors.statusAmber,
                    ),
                  if (isSelected)
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(model.fileName),
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(l10n.t('localModelLibraryUseSelected')),
                    ),
                  if (isSelected)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () =>
                              _startSelectedModel(enableProviderPreset: false),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(l10n.t('localModelStartServer')),
                    ),
                  if (isSelected)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () =>
                              _startSelectedModel(enableProviderPreset: true),
                      icon: const Icon(Icons.flash_on_outlined),
                      label: Text(l10n.t('localModelStartAndEnable')),
                    ),
                  if (isSelected || (isActive && _state.running))
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _openChat,
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: Text(l10n.t('localModelOpenChatAction')),
                    ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _deleteModel(model),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l10n.t('providerDetailRemoveAction')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
