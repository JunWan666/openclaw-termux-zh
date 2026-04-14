import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/ai_provider.dart';
import '../models/custom_provider_preset.dart';
import '../services/local_model_chat_service.dart';
import '../services/local_model_service.dart';
import '../services/provider_config_service.dart';

enum LocalModelChatSessionSource {
  local,
  saved,
  manual,
}

class LocalModelChatSessionConfig {
  const LocalModelChatSessionConfig({
    required this.source,
    required this.displayName,
    required this.endpointUrl,
    required this.modelId,
    required this.compatibility,
    this.apiKey = '',
    this.modelFileName,
    this.providerId,
    this.sourceLabel = '',
  });

  final LocalModelChatSessionSource source;
  final String displayName;
  final String endpointUrl;
  final String modelId;
  final CustomProviderCompatibility compatibility;
  final String apiKey;
  final String? modelFileName;
  final String? providerId;
  final String sourceLabel;

  String get sessionKey =>
      '$source|${providerId ?? ''}|$endpointUrl|$modelId|${compatibility.name}';

  bool sameTarget(LocalModelChatSessionConfig other) {
    return sessionKey == other.sessionKey;
  }
}

class LocalModelChatSettingsResult {
  const LocalModelChatSettingsResult({
    required this.session,
    required this.streamOutput,
    required this.thinkingEnabled,
    required this.showReasoning,
    required this.headerExpanded,
  });

  final LocalModelChatSessionConfig session;
  final bool streamOutput;
  final bool thinkingEnabled;
  final bool showReasoning;
  final bool headerExpanded;
}

class LocalModelChatSettingsScreen extends StatefulWidget {
  const LocalModelChatSettingsScreen({
    super.key,
    required this.localSession,
    required this.currentSession,
    required this.streamOutput,
    required this.thinkingEnabled,
    required this.showReasoning,
    required this.headerExpanded,
  });

  final LocalModelChatSessionConfig localSession;
  final LocalModelChatSessionConfig currentSession;
  final bool streamOutput;
  final bool thinkingEnabled;
  final bool showReasoning;
  final bool headerExpanded;

  @override
  State<LocalModelChatSettingsScreen> createState() =>
      _LocalModelChatSettingsScreenState();
}

class _LocalModelChatSettingsScreenState
    extends State<LocalModelChatSettingsScreen> {
  final _manualNameController = TextEditingController();
  final _manualBaseUrlController = TextEditingController();
  final _manualModelController = TextEditingController();
  final _manualApiKeyController = TextEditingController();

  bool _loadingSavedTargets = true;
  bool _obscureManualApiKey = true;
  bool _streamOutput = true;
  bool _thinkingEnabled = false;
  bool _showReasoning = true;
  bool _headerExpanded = true;
  int _unsupportedSavedCount = 0;

  late LocalModelChatSessionSource _source;
  late CustomProviderCompatibility _manualCompatibility;
  List<_SavedChatTarget> _savedTargets = const <_SavedChatTarget>[];
  String? _selectedSavedTargetKey;

  _SavedChatTarget? get _selectedSavedTarget {
    final selectedKey = _selectedSavedTargetKey;
    if (selectedKey == null) {
      return null;
    }
    for (final target in _savedTargets) {
      if (target.key == selectedKey) {
        return target;
      }
    }
    return null;
  }

  CustomProviderCompatibility get _effectiveCompatibility {
    switch (_source) {
      case LocalModelChatSessionSource.local:
        return widget.localSession.compatibility;
      case LocalModelChatSessionSource.saved:
        return _selectedSavedTarget?.session.compatibility ??
            CustomProviderCompatibility.openaiChatCompletions;
      case LocalModelChatSessionSource.manual:
        return _manualCompatibility;
    }
  }

  @override
  void initState() {
    super.initState();
    _source = widget.currentSession.source;
    _streamOutput = widget.streamOutput;
    _thinkingEnabled = widget.thinkingEnabled;
    _showReasoning = widget.showReasoning;
    _headerExpanded = widget.headerExpanded;
    _manualCompatibility = _supportedManualCompatibilities.contains(
      widget.currentSession.compatibility,
    )
        ? widget.currentSession.compatibility
        : CustomProviderCompatibility.openaiChatCompletions;
    _seedManualFields(widget.currentSession);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSavedTargets();
    });
  }

  @override
  void dispose() {
    _manualNameController.dispose();
    _manualBaseUrlController.dispose();
    _manualModelController.dispose();
    _manualApiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedTargets() async {
    final l10n = context.l10n;
    final config = await ProviderConfigService.readConfig();
    final providers = Map<String, dynamic>.from(
      config['providers'] as Map? ?? const <String, dynamic>{},
    );
    final customPresets = List<CustomProviderPreset>.from(
      config['customPresets'] as List? ?? const <CustomProviderPreset>[],
    );
    final presetById = <String, CustomProviderPreset>{
      for (final preset in customPresets) preset.providerId: preset,
    };
    final providerById = <String, AiProvider>{
      for (final provider in AiProvider.all) provider.id: provider,
    };

    final targets = <_SavedChatTarget>[];
    var unsupportedCount = 0;

    for (final entry in providers.entries) {
      final providerId = entry.key;
      final raw = entry.value;
      if (raw is! Map) {
        continue;
      }
      final normalized = raw.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final target = _savedTargetFromProviderEntry(
        l10n,
        providerId: providerId,
        providerConfig: normalized,
        preset: presetById[providerId],
        provider: providerById[providerId],
      );
      if (target == null) {
        unsupportedCount += 1;
        continue;
      }
      targets.add(target);
    }

    targets.sort((left, right) => left.label.compareTo(right.label));

    String? selectedKey;
    if (widget.currentSession.source == LocalModelChatSessionSource.saved) {
      for (final target in targets) {
        if (target.session.sameTarget(widget.currentSession)) {
          selectedKey = target.key;
          break;
        }
      }
    }
    selectedKey ??= targets.isNotEmpty ? targets.first.key : null;

    if (!mounted) {
      return;
    }
    setState(() {
      _savedTargets = targets;
      _unsupportedSavedCount = unsupportedCount;
      _selectedSavedTargetKey = selectedKey;
      _loadingSavedTargets = false;
      if (_source == LocalModelChatSessionSource.saved && targets.isEmpty) {
        _source = LocalModelChatSessionSource.local;
      }
    });
  }

  _SavedChatTarget? _savedTargetFromProviderEntry(
    AppLocalizations l10n, {
    required String providerId,
    required Map<String, dynamic> providerConfig,
    required CustomProviderPreset? preset,
    required AiProvider? provider,
  }) {
    final baseUrl = providerConfig['baseUrl']?.toString().trim() ?? '';
    final modelId = providerConfig['model']?.toString().trim() ?? '';
    if (baseUrl.isEmpty || modelId.isEmpty) {
      return null;
    }

    final compatibility =
        _compatibilityForSavedTarget(providerId, preset: preset);
    if (compatibility == null) {
      return null;
    }

    final displayName = (preset?.displayName.trim().isNotEmpty == true
            ? preset!.displayName
            : '')
        .trim();
    final providerLabel = displayName.isNotEmpty
        ? displayName
        : provider != null
            ? provider.name(l10n)
            : providerId;
    final sourceLabel = provider != null
        ? provider.name(l10n)
        : l10n.t('localModelChatSavedConfigSource');

    return _SavedChatTarget(
      key: '$providerId|$modelId|$baseUrl',
      label: '$providerLabel · $modelId',
      subtitle:
          '${_compatibilityLabel(l10n, compatibility)} · ${_shortBaseUrl(baseUrl)}',
      session: LocalModelChatSessionConfig(
        source: LocalModelChatSessionSource.saved,
        displayName: providerLabel,
        endpointUrl: baseUrl,
        modelId: modelId,
        compatibility: compatibility,
        apiKey: providerConfig['apiKey']?.toString().trim() ?? '',
        providerId: providerId,
        sourceLabel: sourceLabel,
      ),
    );
  }

  CustomProviderCompatibility? _compatibilityForSavedTarget(
    String providerId, {
    required CustomProviderPreset? preset,
  }) {
    if (preset != null) {
      switch (preset.compatibility) {
        case CustomProviderCompatibility.autoDetect:
        case CustomProviderCompatibility.openaiChatCompletions:
        case CustomProviderCompatibility.zhipuChatCompletions:
        case CustomProviderCompatibility.openaiResponses:
          return preset.compatibility == CustomProviderCompatibility.autoDetect
              ? CustomProviderCompatibility.openaiChatCompletions
              : preset.compatibility;
        case CustomProviderCompatibility.anthropicMessages:
        case CustomProviderCompatibility.googleGenerativeAi:
          return null;
      }
    }

    switch (providerId) {
      case 'zhipu':
        return CustomProviderCompatibility.zhipuChatCompletions;
      case 'openai':
      case 'qwen':
      case 'minimax':
      case 'doubao':
      case 'openrouter':
      case 'nvidia':
      case 'deepseek':
      case 'xai':
      case LocalModelService.localProviderId:
        return CustomProviderCompatibility.openaiChatCompletions;
      default:
        return null;
    }
  }

  void _seedManualFields(LocalModelChatSessionConfig session) {
    _manualNameController.text = session.displayName;
    _manualBaseUrlController.text = session.endpointUrl;
    _manualModelController.text = session.modelId;
    _manualApiKeyController.text = session.apiKey;
  }

  String _compatibilityLabel(
    AppLocalizations l10n,
    CustomProviderCompatibility compatibility,
  ) {
    switch (compatibility) {
      case CustomProviderCompatibility.openaiChatCompletions:
        return l10n.t('customProviderCompatibilityOpenai');
      case CustomProviderCompatibility.zhipuChatCompletions:
        return l10n.t('customProviderCompatibilityZhipu');
      case CustomProviderCompatibility.openaiResponses:
        return l10n.t('customProviderCompatibilityOpenaiResponses');
      case CustomProviderCompatibility.autoDetect:
        return l10n.t('customProviderCompatibilityAuto');
      case CustomProviderCompatibility.anthropicMessages:
        return l10n.t('customProviderCompatibilityAnthropic');
      case CustomProviderCompatibility.googleGenerativeAi:
        return l10n.t('customProviderCompatibilityGoogle');
    }
  }

  String _shortBaseUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasAuthority) {
      return value;
    }
    final path = uri.path.trim().isEmpty ? '' : uri.path;
    return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}$path';
  }

  bool _isValidBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null && uri.hasScheme && uri.hasAuthority;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _save() {
    final l10n = context.l10n;
    late final LocalModelChatSessionConfig session;

    switch (_source) {
      case LocalModelChatSessionSource.local:
        session = widget.localSession;
        break;
      case LocalModelChatSessionSource.saved:
        final selectedTarget = _selectedSavedTarget;
        if (selectedTarget == null) {
          _showError(l10n.t('localModelChatSavedConfigEmpty'));
          return;
        }
        session = selectedTarget.session;
        break;
      case LocalModelChatSessionSource.manual:
        final baseUrl = _manualBaseUrlController.text.trim();
        final modelId = _manualModelController.text.trim();
        if (!_isValidBaseUrl(baseUrl)) {
          _showError(l10n.t('providerDetailEndpointInvalid'));
          return;
        }
        if (modelId.isEmpty) {
          _showError(l10n.t('customProviderModelIdEmpty'));
          return;
        }
        final displayName = _manualNameController.text.trim().isEmpty
            ? modelId
            : _manualNameController.text.trim();
        session = LocalModelChatSessionConfig(
          source: LocalModelChatSessionSource.manual,
          displayName: displayName,
          endpointUrl: baseUrl,
          modelId: modelId,
          compatibility: _manualCompatibility,
          apiKey: _manualApiKeyController.text.trim(),
          sourceLabel: l10n.t('localModelChatManualSource'),
        );
        break;
    }

    Navigator.of(context).pop(
      LocalModelChatSettingsResult(
        session: session,
        streamOutput: _streamOutput,
        thinkingEnabled: _thinkingEnabled,
        showReasoning: _showReasoning,
        headerExpanded: _headerExpanded,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final compatibility = _effectiveCompatibility;
    final streamSupported = LocalModelChatService.supportsStreaming(
      compatibility,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('localModelChatSettingsTitle')),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(l10n.t('commonDone')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.t('localModelChatSettingsIntro'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.55,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('localModelChatSessionSourceTitle'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(l10n.t('localModelChatSourceLocal')),
                        selected: _source == LocalModelChatSessionSource.local,
                        onSelected: (_) {
                          setState(() =>
                              _source = LocalModelChatSessionSource.local);
                        },
                      ),
                      ChoiceChip(
                        label: Text(l10n.t('localModelChatSourceSaved')),
                        selected: _source == LocalModelChatSessionSource.saved,
                        onSelected: _savedTargets.isEmpty
                            ? null
                            : (_) {
                                setState(() {
                                  _source = LocalModelChatSessionSource.saved;
                                });
                              },
                      ),
                      ChoiceChip(
                        label: Text(l10n.t('localModelChatSourceManual')),
                        selected: _source == LocalModelChatSessionSource.manual,
                        onSelected: (_) {
                          setState(() =>
                              _source = LocalModelChatSessionSource.manual);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildSourceSection(theme, l10n),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('localModelChatSessionBehaviorTitle'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    value: _streamOutput,
                    onChanged: (value) {
                      setState(() => _streamOutput = value);
                    },
                    title: Text(l10n.t('localModelChatStreamToggle')),
                    subtitle: Text(
                      streamSupported
                          ? l10n.t('localModelChatStreamToggleHint')
                          : l10n.t('localModelChatStreamUnsupportedHint'),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile.adaptive(
                    value: _thinkingEnabled,
                    onChanged: (value) {
                      setState(() => _thinkingEnabled = value);
                    },
                    title: Text(l10n.t('localModelChatThinkingToggle')),
                    subtitle: Text(
                      l10n.t('localModelChatThinkingToggleHint'),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile.adaptive(
                    value: _showReasoning,
                    onChanged: (value) {
                      setState(() => _showReasoning = value);
                    },
                    title: Text(l10n.t('localModelChatShowReasoningToggle')),
                    subtitle: Text(
                      l10n.t('localModelChatShowReasoningToggleHint'),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile.adaptive(
                    value: _headerExpanded,
                    onChanged: (value) {
                      setState(() => _headerExpanded = value);
                    },
                    title: Text(l10n.t('localModelChatHeaderExpandedToggle')),
                    subtitle: Text(
                      l10n.t('localModelChatHeaderExpandedToggleHint'),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceSection(ThemeData theme, AppLocalizations l10n) {
    switch (_source) {
      case LocalModelChatSessionSource.local:
        return _buildInfoBox(
          theme,
          title: widget.localSession.displayName,
          body: [
            '${l10n.t('localModelChatModelLabel')}: ${widget.localSession.modelId}',
            '${l10n.t('providerDetailEndpoint')}: ${widget.localSession.endpointUrl}',
            if ((widget.localSession.modelFileName ?? '').trim().isNotEmpty)
              widget.localSession.modelFileName!,
          ].join('\n'),
        );
      case LocalModelChatSessionSource.saved:
        if (_loadingSavedTargets) {
          return Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(l10n.t('localModelChatSavedConfigLoading')),
              ),
            ],
          );
        }
        if (_savedTargets.isEmpty) {
          return Text(
            l10n.t('localModelChatSavedConfigEmptyHint'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey(_selectedSavedTargetKey ?? 'saved-target-empty'),
              initialValue: _selectedSavedTargetKey,
              items: [
                for (final target in _savedTargets)
                  DropdownMenuItem(
                    value: target.key,
                    child: Text(target.label),
                  ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() => _selectedSavedTargetKey = value);
              },
              decoration: InputDecoration(
                labelText: l10n.t('localModelChatSavedConfigPicker'),
              ),
            ),
            const SizedBox(height: 12),
            if (_selectedSavedTarget != null)
              _buildInfoBox(
                theme,
                title: _selectedSavedTarget!.label,
                body: [
                  _selectedSavedTarget!.subtitle,
                  '${l10n.t('providerDetailEndpoint')}: ${_selectedSavedTarget!.session.endpointUrl}',
                ].join('\n'),
              ),
            if (_unsupportedSavedCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                l10n.t(
                  'localModelChatSavedConfigUnsupportedHint',
                  {'count': _unsupportedSavedCount},
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ],
        );
      case LocalModelChatSessionSource.manual:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<CustomProviderCompatibility>(
              key: ValueKey(_manualCompatibility.name),
              initialValue: _manualCompatibility,
              items: [
                for (final compatibility in _supportedManualCompatibilities)
                  DropdownMenuItem(
                    value: compatibility,
                    child: Text(_compatibilityLabel(l10n, compatibility)),
                  ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() => _manualCompatibility = value);
              },
              decoration: InputDecoration(
                labelText: l10n.t('localModelChatManualCompatibilityLabel'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _manualNameController,
              decoration: InputDecoration(
                labelText: l10n.t('localModelChatManualNameLabel'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _manualBaseUrlController,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: l10n.t('providerDetailEndpoint'),
                hintText: _manualCompatibility ==
                        CustomProviderCompatibility.zhipuChatCompletions
                    ? 'https://open.bigmodel.cn/api/paas/v4'
                    : 'https://api.example.com/v1',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _manualModelController,
              decoration: InputDecoration(
                labelText: l10n.t('customProviderModelId'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _manualApiKeyController,
              obscureText: _obscureManualApiKey,
              decoration: InputDecoration(
                labelText: l10n.t('providerDetailApiKey'),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(
                        () => _obscureManualApiKey = !_obscureManualApiKey);
                  },
                  icon: Icon(
                    _obscureManualApiKey
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.t('localModelChatManualHint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        );
    }
  }

  Widget _buildInfoBox(
    ThemeData theme, {
    required String title,
    required String body,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(70),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            body,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedChatTarget {
  const _SavedChatTarget({
    required this.key,
    required this.label,
    required this.subtitle,
    required this.session,
  });

  final String key;
  final String label;
  final String subtitle;
  final LocalModelChatSessionConfig session;
}

const _supportedManualCompatibilities = <CustomProviderCompatibility>[
  CustomProviderCompatibility.openaiChatCompletions,
  CustomProviderCompatibility.zhipuChatCompletions,
  CustomProviderCompatibility.openaiResponses,
];
