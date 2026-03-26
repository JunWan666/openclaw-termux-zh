import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/app_localizations.dart';
import '../models/ai_provider.dart';
import '../models/custom_provider_preset.dart';
import '../services/custom_provider_connection_test_service.dart';
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

  final _connectionTestService = CustomProviderConnectionTestService();
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
  bool _testingConnection = false;
  bool _obscureKey = true;
  bool _didChange = false;
  String? _lastTestFingerprint;
  CustomProviderConnectionTestResult? _lastConnectionTestResult;

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

  String get _currentConnectionFingerprint => [
        _compatibility.name,
        _baseUrlController.text.trim(),
        _apiKeyController.text.trim(),
        _modelIdController.text.trim(),
      ].join('\u0000');

  bool get _hasFreshConnectionTest =>
      _lastTestFingerprint == _currentConnectionFingerprint &&
      _lastConnectionTestResult != null;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController();
    _apiKeyController = TextEditingController();
    _modelIdController = TextEditingController();
    _providerIdController = TextEditingController();
    _aliasController = TextEditingController();
    _baseUrlController.addListener(_handleConnectionFieldChanged);
    _apiKeyController.addListener(_handleConnectionFieldChanged);
    _modelIdController.addListener(_handleConnectionFieldChanged);
    _loadPresets();
  }

  @override
  void dispose() {
    _baseUrlController.removeListener(_handleConnectionFieldChanged);
    _apiKeyController.removeListener(_handleConnectionFieldChanged);
    _modelIdController.removeListener(_handleConnectionFieldChanged);
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

  void _handleConnectionFieldChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _clearConnectionTestState() {
    _lastTestFingerprint = null;
    _lastConnectionTestResult = null;
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
      _clearConnectionTestState();
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
      _clearConnectionTestState();
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

  bool _validateConnectionInputs() {
    final l10n = context.l10n;
    final baseUrl = _baseUrlController.text.trim();
    if (!_isValidBaseUrl(baseUrl)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('providerDetailEndpointInvalid'))),
      );
      return false;
    }

    final modelId = _modelIdController.text.trim();
    if (modelId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('customProviderModelIdEmpty'))),
      );
      return false;
    }

    return true;
  }

  String _presetLabel(CustomProviderPreset preset) {
    final detail = preset.providerId == preset.displayName
        ? preset.modelId
        : preset.providerId;
    return '${preset.displayName} ($detail)';
  }

  Future<CustomProviderConnectionTestResult?> _runConnectionTest() async {
    if (!_validateConnectionInputs()) {
      return null;
    }

    final fingerprint = _currentConnectionFingerprint;
    setState(() => _testingConnection = true);

    try {
      final result = await _connectionTestService.testConnection(
        compatibility: _compatibility,
        apiKey: _apiKeyController.text.trim(),
        baseUrl: _baseUrlController.text.trim(),
        modelId: _modelIdController.text.trim(),
      );
      if (!mounted) {
        return result;
      }
      setState(() {
        _lastTestFingerprint = fingerprint;
        _lastConnectionTestResult = result;
      });
      return result;
    } finally {
      if (mounted) {
        setState(() => _testingConnection = false);
      }
    }
  }

  Future<bool> _ensureConnectionCheckedBeforeSave() async {
    final currentResult =
        _hasFreshConnectionTest ? _lastConnectionTestResult : null;
    if (currentResult?.success == true) {
      return true;
    }

    final result = currentResult ?? await _runConnectionTest();
    if (result == null) {
      return false;
    }

    if (result.success) {
      return true;
    }

    if (!mounted) {
      return false;
    }

    final l10n = context.l10n;
    final detail = _connectionTestDetailText(l10n, result);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.t('customProviderSaveFailedConnectionTitle')),
        content: Text(
          [
            l10n.t('customProviderSaveFailedConnectionBody'),
            if (detail != null && detail.isNotEmpty)
              l10n.t('customProviderSaveFailedConnectionReason', {
                'reason': detail,
              }),
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.t('commonCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.t('commonContinue')),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  String _compatibilityText(
    AppLocalizations l10n,
    CustomProviderCompatibility compatibility,
  ) {
    return l10n.t(compatibility.labelKey);
  }

  String? _connectionTestDetailText(
    AppLocalizations l10n,
    CustomProviderConnectionTestResult result,
  ) {
    final parts = <String>[];
    if (result.statusCode != null) {
      parts.add(
        l10n.t('customProviderTestHttpStatus', {
          'status': result.statusCode,
        }),
      );
    }
    final detail = result.detail?.trim();
    if (detail != null && detail.isNotEmpty) {
      parts.add(detail);
    }
    if (parts.isEmpty) {
      return null;
    }
    return parts.join(' · ');
  }

  Widget _buildConnectionTestCard(ThemeData theme, AppLocalizations l10n) {
    final result = _lastConnectionTestResult;
    final isFresh = _hasFreshConnectionTest;
    final bool isSuccess = isFresh && result?.success == true;
    final bool isFailure = isFresh && result?.success == false;
    final bool isStale = result != null && !isFresh;

    final Color accentColor;
    final IconData icon;
    final String title;

    if (_testingConnection) {
      accentColor = theme.colorScheme.primary;
      icon = Icons.sync;
      title = l10n.t('customProviderTestStatusChecking');
    } else if (isSuccess) {
      accentColor = AppColors.statusGreen;
      icon = Icons.check_circle_outline;
      title = l10n.t('customProviderTestStatusSuccess');
    } else if (isFailure) {
      accentColor = AppColors.statusRed;
      icon = Icons.error_outline;
      title = l10n.t('customProviderTestStatusFailure');
    } else if (isStale) {
      accentColor = AppColors.statusAmber;
      icon = Icons.history_toggle_off;
      title = l10n.t('customProviderTestStatusStale');
    } else {
      accentColor = theme.colorScheme.onSurfaceVariant;
      icon = Icons.radio_button_unchecked;
      title = l10n.t('customProviderTestStatusUntested');
    }

    final detailLines = <String>[];
    if (result != null) {
      if (result.autoDetected) {
        detailLines.add(
          l10n.t('customProviderTestAutoDetectedHint', {
            'compatibility': _compatibilityText(l10n, result.compatibility),
          }),
        );
      } else if (isFresh) {
        detailLines.add(
          l10n.t('customProviderTestCompatibilityHint', {
            'compatibility': _compatibilityText(l10n, result.compatibility),
          }),
        );
      }

      final detail = _connectionTestDetailText(l10n, result);
      if (detail != null && detail.isNotEmpty) {
        detailLines.add(detail);
      }
      detailLines.add(
        l10n.t('customProviderTestEndpointHint', {
          'endpoint': result.endpoint.toString(),
        }),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accentColor.withAlpha(12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withAlpha(40)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: accentColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                for (final line in detailLines) ...[
                  const SizedBox(height: 4),
                  Text(
                    line,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    if (!_validateConnectionInputs()) {
      return;
    }

    final providerId = _providerIdController.text.trim();
    if (providerId.contains('/')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('customProviderProviderIdInvalid'))),
      );
      return;
    }

    final allowSave = await _ensureConnectionCheckedBeforeSave();
    if (!allowSave || !mounted) {
      return;
    }

    final baseUrl = _baseUrlController.text.trim();
    final modelId = _modelIdController.text.trim();
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
                  const SizedBox(height: 24),
                  _fieldTitle(
                    theme,
                    l10n.t('customProviderConnectionTestLabel'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _testingConnection || _saving
                        ? null
                        : _runConnectionTest,
                    icon: _testingConnection
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.onSurface,
                            ),
                          )
                        : const Icon(Icons.wifi_tethering_outlined),
                    label: Text(
                      _testingConnection
                          ? l10n.t('customProviderTestingAction')
                          : l10n.t('customProviderTestAction'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildConnectionTestCard(theme, l10n),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _saving || _testingConnection ? null : _save,
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
