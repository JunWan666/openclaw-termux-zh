import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/app_localizations.dart';
import '../models/ai_provider.dart';
import '../models/custom_provider_preset.dart';
import '../services/provider_config_service.dart';

class CustomProviderDetailScreen extends StatefulWidget {
  const CustomProviderDetailScreen({super.key});

  @override
  State<CustomProviderDetailScreen> createState() =>
      _CustomProviderDetailScreenState();
}

class _CustomProviderDetailScreenState
    extends State<CustomProviderDetailScreen> {
  static const _newPresetValue = '__new_preset__';

  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelIdController;
  late final TextEditingController _providerIdController;
  late final TextEditingController _aliasController;

  List<CustomProviderPreset> _presets = const [];
  String? _activeModel;
  String _selectedPresetValue = _newPresetValue;
  CustomProviderCompatibility _compatibility =
      CustomProviderCompatibility.openaiChatCompletions;
  bool _loading = true;
  bool _saving = false;
  bool _removing = false;
  bool _obscureKey = true;
  bool _didChange = false;

  CustomProviderPreset? get _selectedPreset {
    if (_selectedPresetValue == _newPresetValue) {
      return null;
    }
    for (final preset in _presets) {
      if (preset.providerId == _selectedPresetValue) {
        return preset;
      }
    }
    return null;
  }

  bool get _isEditingExisting => _selectedPreset != null;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController();
    _apiKeyController = TextEditingController();
    _modelIdController = TextEditingController();
    _providerIdController = TextEditingController();
    _aliasController = TextEditingController();
    _loadPresets();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelIdController.dispose();
    _providerIdController.dispose();
    _aliasController.dispose();
    super.dispose();
  }

  Future<bool> _handleBack() async {
    Navigator.of(context).pop(_didChange);
    return false;
  }

  Future<void> _loadPresets({String? preferredProviderId}) async {
    final config = await ProviderConfigService.readConfig();
    final presets = List<CustomProviderPreset>.from(
      config['customPresets'] as List? ?? const <CustomProviderPreset>[],
    );
    final activeModel = config['activeModel'] as String?;

    String? selectedProviderId = preferredProviderId;
    if (selectedProviderId == null && activeModel != null) {
      selectedProviderId =
          ProviderConfigService.providerIdFromModelRef(activeModel);
      if (!presets.any((preset) => preset.providerId == selectedProviderId)) {
        selectedProviderId = null;
      }
    }
    selectedProviderId ??= presets.isNotEmpty ? presets.first.providerId : null;

    if (!mounted) {
      return;
    }

    setState(() {
      _presets = presets;
      _activeModel = activeModel;
      _loading = false;
    });

    if (selectedProviderId != null) {
      final preset = presets.firstWhere(
        (item) => item.providerId == selectedProviderId,
      );
      _applyPreset(preset);
    } else {
      _applyBlankPreset();
    }
  }

  void _applyPreset(CustomProviderPreset preset) {
    setState(() {
      _selectedPresetValue = preset.providerId;
      _compatibility = preset.compatibility;
      _baseUrlController.text = preset.baseUrl;
      _apiKeyController.text = preset.apiKey;
      _modelIdController.text = preset.modelId;
      _providerIdController.text = preset.providerId;
      _aliasController.text = preset.alias;
    });
  }

  void _applyBlankPreset() {
    setState(() {
      _selectedPresetValue = _newPresetValue;
      _compatibility = CustomProviderCompatibility.openaiChatCompletions;
      _baseUrlController.text = AiProvider.customOpenai.baseUrl;
      _apiKeyController.clear();
      _modelIdController.clear();
      _providerIdController.clear();
      _aliasController.clear();
    });
  }

  bool _isValidBaseUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.hasScheme && uri.hasAuthority;
  }

  String _presetLabel(CustomProviderPreset preset) {
    final detail = preset.providerId == preset.displayName
        ? preset.modelId
        : preset.providerId;
    return '${preset.displayName} ($detail)';
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final baseUrl = _baseUrlController.text.trim();
    if (!_isValidBaseUrl(baseUrl)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('providerDetailEndpointInvalid'))),
      );
      return;
    }

    final modelId = _modelIdController.text.trim();
    if (modelId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('customProviderModelIdEmpty'))),
      );
      return;
    }

    final providerId = _providerIdController.text.trim();
    if (providerId.contains('/')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('customProviderProviderIdInvalid'))),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final preset = await ProviderConfigService.saveCustomProviderPreset(
        compatibility: _compatibility,
        apiKey: _apiKeyController.text.trim(),
        baseUrl: baseUrl,
        modelId: modelId,
        providerId: providerId.isEmpty ? null : providerId,
        alias: _aliasController.text.trim(),
        previousProviderId: _selectedPreset?.providerId,
      );
      if (!mounted) {
        return;
      }
      _didChange = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t('customProviderSaved', {'preset': preset.displayName}),
          ),
        ),
      );
      await _loadPresets(preferredProviderId: preset.providerId);
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.t('providerDetailSaveFailed', {'error': '$e'})),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _remove() async {
    final l10n = context.l10n;
    final preset = _selectedPreset;
    if (preset == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          l10n.t('customProviderRemoveTitle', {'preset': preset.displayName}),
        ),
        content: Text(l10n.t('customProviderRemoveBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.t('commonCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.t('providerDetailRemoveAction')),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _removing = true);
    try {
      await ProviderConfigService.removeCustomProviderPreset(
        providerId: preset.providerId,
      );
      if (!mounted) {
        return;
      }
      _didChange = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t('customProviderRemoved', {'preset': preset.displayName}),
          ),
        ),
      );
      await _loadPresets();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t('providerDetailRemoveFailed', {'error': '$e'}),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _removing = false);
      }
    }
  }

  Widget _fieldTitle(ThemeData theme, String text) {
    return Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final iconBg = isDark ? AppColors.darkSurfaceAlt : const Color(0xFFF3F4F6);
    CustomProviderPreset? activeCustomPreset;
    final activeModel = _activeModel;
    if (activeModel != null && activeModel.isNotEmpty) {
      for (final preset in _presets) {
        if (preset.modelRef == activeModel) {
          activeCustomPreset = preset;
          break;
        }
      }
    }

    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.of(context).pop(_didChange);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(AiProvider.customOpenai.name(l10n)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _handleBack(),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: iconBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              AiProvider.customOpenai.icon,
                              color: AiProvider.customOpenai.color,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AiProvider.customOpenai.name(l10n),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  AiProvider.customOpenai.description(l10n),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (activeCustomPreset != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    l10n.t(
                                      'customProviderActivePresetHint',
                                      {
                                        'preset': activeCustomPreset.displayName
                                      },
                                    ),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColors.statusGreen,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _fieldTitle(theme, l10n.t('customProviderPresetLabel')),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedPresetValue,
                    items: [
                      DropdownMenuItem(
                        value: _newPresetValue,
                        child: Text(l10n.t('customProviderPresetNewAction')),
                      ),
                      ..._presets.map(
                        (preset) => DropdownMenuItem(
                          value: preset.providerId,
                          child: Text(_presetLabel(preset)),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      if (value == _newPresetValue) {
                        _applyBlankPreset();
                        return;
                      }
                      final preset = _presets.firstWhere(
                        (item) => item.providerId == value,
                      );
                      _applyPreset(preset);
                    },
                  ),
                  const SizedBox(height: 24),
                  _fieldTitle(theme, l10n.t('customProviderCompatibility')),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<CustomProviderCompatibility>(
                    initialValue: _compatibility,
                    items: [
                      for (final item in CustomProviderCompatibility.values)
                        DropdownMenuItem(
                          value: item,
                          child: Text(l10n.t(item.labelKey)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _compatibility = value;
                        final normalized =
                            ProviderConfigService.normalizeCustomBaseUrl(
                          _baseUrlController.text,
                          value,
                        );
                        if (normalized.isNotEmpty) {
                          _baseUrlController.text = normalized;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  _fieldTitle(theme, l10n.t('providerDetailEndpoint')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _baseUrlController,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      hintText: AiProvider.customOpenai.baseUrl,
                      helperText: l10n
                          .t('providerDetailEndpointHelperOpenaiCompatible'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _fieldTitle(theme, l10n.t('providerDetailApiKey')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: _obscureKey,
                    decoration: InputDecoration(
                      hintText: AiProvider.customOpenai.apiKeyHint,
                      helperText: l10n.t('customProviderApiKeyHelper'),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureKey ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() => _obscureKey = !_obscureKey);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _fieldTitle(theme, l10n.t('customProviderModelId')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _modelIdController,
                    decoration: InputDecoration(
                      hintText:
                          l10n.t('providerDetailModelHintOpenaiCompatible'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _fieldTitle(theme, l10n.t('customProviderProviderId')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _providerIdController,
                    decoration: InputDecoration(
                      hintText: 'custom-openai',
                      helperText: l10n.t('customProviderProviderIdHelper'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _fieldTitle(theme, l10n.t('customProviderAlias')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _aliasController,
                    decoration: InputDecoration(
                      hintText: l10n.t('customProviderAliasPlaceholder'),
                      helperText: l10n.t('customProviderAliasHelper'),
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(l10n.t('providerDetailSaveAction')),
                  ),
                  if (_isEditingExisting) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _removing ? null : _remove,
                      child: _removing
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.t('providerDetailRemoveConfiguration')),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
