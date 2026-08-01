import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../l10n/app_localizations.dart';
import '../models/ai_provider.dart';
import '../models/custom_provider_preset.dart';
import '../providers/gateway_provider.dart';
import '../services/custom_provider_connection_test_service.dart';
import '../services/provider_config_service.dart';
import '../services/provider_model_catalog_service.dart';

/// Form screen to configure API key and model for a single AI provider.
class ProviderDetailScreen extends StatefulWidget {
  final AiProvider provider;
  final String? existingApiKey;
  final String? existingBaseUrl;
  final String? existingModel;

  const ProviderDetailScreen({
    super.key,
    required this.provider,
    this.existingApiKey,
    this.existingBaseUrl,
    this.existingModel,
  });

  @override
  State<ProviderDetailScreen> createState() => _ProviderDetailScreenState();
}

class _ProviderDetailScreenState extends State<ProviderDetailScreen> {
  static const _customModelSentinel = '__custom__';

  late final TextEditingController _apiKeyController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _customModelController;
  final _modelCatalogService = ProviderModelCatalogService();
  final _connectionTestService = CustomProviderConnectionTestService();
  late List<String> _availableModels;
  late String _selectedModel;
  bool _isCustomModel = false;
  bool _obscureKey = true;
  bool _saving = false;
  bool _removing = false;
  bool _fetchingModels = false;
  bool _testingConnection = false;
  CustomProviderConnectionTestResult? _connectionTestResult;

  bool get _isConfigured =>
      widget.existingApiKey != null && widget.existingApiKey!.isNotEmpty;

  /// Returns the effective model name to save.
  String get _effectiveModel =>
      _isCustomModel ? _customModelController.text.trim() : _selectedModel;

  bool get _supportsCustomBaseUrl => widget.provider.supportsCustomBaseUrl;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController(
        text: widget.existingApiKey ?? widget.provider.defaultApiKey ?? '');
    _baseUrlController = TextEditingController(
      text: widget.existingBaseUrl ?? widget.provider.baseUrl,
    );
    _customModelController = TextEditingController();
    _availableModels = List<String>.from(widget.provider.defaultModels);
    _apiKeyController.addListener(_clearConnectionTestResult);
    _baseUrlController.addListener(_clearConnectionTestResult);
    _customModelController.addListener(_clearConnectionTestResult);

    final existing = widget.existingModel ??
        (widget.provider.defaultModels.isNotEmpty
            ? widget.provider.defaultModels.first
            : '');
    if (widget.provider.defaultModels.isEmpty) {
      _selectedModel = _customModelSentinel;
      _isCustomModel = true;
      _customModelController.text = existing;
    } else if (widget.provider.defaultModels.contains(existing)) {
      _selectedModel = existing;
    } else {
      // Existing model is not in the predefined list — treat as custom
      _selectedModel = _customModelSentinel;
      _isCustomModel = true;
      _customModelController.text = existing;
    }
  }

  @override
  void dispose() {
    _apiKeyController.removeListener(_clearConnectionTestResult);
    _baseUrlController.removeListener(_clearConnectionTestResult);
    _customModelController.removeListener(_clearConnectionTestResult);
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _customModelController.dispose();
    super.dispose();
  }

  bool _isValidBaseUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.hasScheme && uri.hasAuthority;
  }

  void _clearConnectionTestResult() {
    if (_connectionTestResult != null && mounted) {
      setState(() => _connectionTestResult = null);
    }
  }

  Future<void> _openApiKeyPage() async {
    final url = widget.provider.apiKeyUrl;
    if (url == null) return;

    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(context.l10n.t('providerDetailApiKeyLinkFailed'))),
      );
    }
  }

  Future<void> _fetchModels() async {
    final l10n = context.l10n;
    final apiKey = _apiKeyController.text.trim();
    if (widget.provider.modelCatalogRequiresApiKey && apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('providerDetailApiKeyEmpty'))),
      );
      return;
    }

    final baseUrl = _baseUrlController.text.trim();
    if (!_isValidBaseUrl(baseUrl)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('providerDetailEndpointInvalid'))),
      );
      return;
    }

    setState(() => _fetchingModels = true);
    try {
      final fetched = await _modelCatalogService.fetchModels(
        baseUrl: widget.provider.normalizeBaseUrl(baseUrl),
        apiKey: apiKey,
      );
      final preferred = <String>[
        for (final model in widget.provider.defaultModels)
          if (fetched.contains(model)) model,
        for (final model in fetched)
          if (!widget.provider.defaultModels.contains(model)) model,
      ];
      final currentModel = _effectiveModel;

      if (!mounted) return;
      setState(() {
        _availableModels = preferred;
        if (currentModel.isNotEmpty && preferred.contains(currentModel)) {
          _selectedModel = currentModel;
          _isCustomModel = false;
        } else if (currentModel.isNotEmpty) {
          _selectedModel = _customModelSentinel;
          _isCustomModel = true;
          _customModelController.text = currentModel;
        } else {
          _selectedModel = preferred.first;
          _isCustomModel = false;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t('providerDetailModelsLoaded', {'count': preferred.length}),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.t('providerDetailModelsLoadFailed', {'error': '$error'}),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _fetchingModels = false);
    }
  }

  Future<void> _testConnection() async {
    final l10n = context.l10n;
    final apiKey = _apiKeyController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    final model = _effectiveModel;
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('providerDetailApiKeyEmpty'))),
      );
      return;
    }
    if (!_isValidBaseUrl(baseUrl)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('providerDetailEndpointInvalid'))),
      );
      return;
    }
    if (model.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('providerDetailModelEmpty'))),
      );
      return;
    }

    setState(() {
      _testingConnection = true;
      _connectionTestResult = null;
    });
    final result = await _connectionTestService.testConnection(
      compatibility: CustomProviderCompatibility.openaiChatCompletions,
      baseUrl: widget.provider.normalizeBaseUrl(baseUrl),
      apiKey: apiKey,
      modelId: model,
    );
    if (mounted) {
      setState(() {
        _testingConnection = false;
        _connectionTestResult = result;
      });
    }
  }

  String _connectionResultText(
    AppLocalizations l10n,
    CustomProviderConnectionTestResult result,
  ) {
    if (result.success) {
      return l10n.t('providerDetailConnectionTestSucceeded');
    }
    final detail = result.detail?.trim();
    final fallback = result.statusCode == null
        ? l10n.t('commonUnknown')
        : 'HTTP ${result.statusCode}';
    return l10n.t(
      'providerDetailConnectionTestFailed',
      {'error': detail?.isNotEmpty == true ? detail : fallback},
    );
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final gatewayProvider = context.read<GatewayProvider>();
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('providerDetailApiKeyEmpty'))),
      );
      return;
    }
    final baseUrl = _baseUrlController.text.trim();
    if (_supportsCustomBaseUrl && !_isValidBaseUrl(baseUrl)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('providerDetailEndpointInvalid'))),
      );
      return;
    }
    final model = _effectiveModel;
    if (model.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('providerDetailModelEmpty'))),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final normalizedBaseUrl = _supportsCustomBaseUrl
          ? widget.provider.normalizeBaseUrl(baseUrl)
          : baseUrl;
      await ProviderConfigService.saveProviderConfig(
        provider: widget.provider,
        apiKey: apiKey,
        baseUrl: normalizedBaseUrl,
        model: model,
      );
      await gatewayProvider.applyConfigChanges(
        source: '${widget.provider.id} provider settings',
      );
      if (_supportsCustomBaseUrl) {
        _baseUrlController.text = normalizedBaseUrl;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.t('providerDetailSaved', {
                'provider': widget.provider.name(l10n),
              }),
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.t('providerDetailSaveFailed', {'error': '$e'})),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    final l10n = context.l10n;
    final gatewayProvider = context.read<GatewayProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          l10n.t('providerDetailRemoveTitle', {
            'provider': widget.provider.name(l10n),
          }),
        ),
        content: Text(l10n.t('providerDetailRemoveBody')),
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

    if (confirmed != true) return;

    setState(() => _removing = true);
    try {
      await ProviderConfigService.removeProviderConfig(
          provider: widget.provider);
      await gatewayProvider.applyConfigChanges(
        source: '${widget.provider.id} provider settings',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.t('providerDetailRemoved', {
                'provider': widget.provider.name(l10n),
              }),
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.t('providerDetailRemoveFailed', {'error': '$e'}),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final iconBg = isDark ? AppColors.darkSurfaceAlt : const Color(0xFFF3F4F6);

    return Scaffold(
      appBar: AppBar(title: Text(widget.provider.name(l10n))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Provider header
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
                    child: Icon(widget.provider.icon,
                        color: widget.provider.color),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.provider.name(l10n),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.provider.description(l10n),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.provider.usageNotice(l10n) case final notice?) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer.withAlpha(120),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      notice,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),

          // API Key
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.t('providerDetailApiKey'),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (widget.provider.apiKeyUrl != null)
                TextButton.icon(
                  onPressed: _openApiKeyPage,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(l10n.t('providerDetailGetApiKey')),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _apiKeyController,
            obscureText: _obscureKey,
            decoration: InputDecoration(
              hintText: widget.provider.apiKeyHint,
              suffixIcon: IconButton(
                icon:
                    Icon(_obscureKey ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
          if (_supportsCustomBaseUrl) ...[
            const SizedBox(height: 24),
            Text(
              l10n.t('providerDetailEndpoint'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _baseUrlController,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: widget.provider.baseUrl,
                helperText: widget.provider.endpointHelper(l10n),
              ),
            ),
          ],
          const SizedBox(height: 24),

          // Model selection
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.t('providerDetailModel'),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (widget.provider.supportsModelCatalog)
                IconButton(
                  onPressed: _fetchingModels ? null : _fetchModels,
                  tooltip: l10n.t('providerDetailLoadModels'),
                  icon: _fetchingModels
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_availableModels.isNotEmpty)
            DropdownButtonFormField<String>(
              value: _selectedModel,
              isExpanded: true,
              decoration: const InputDecoration(),
              items: [
                ..._availableModels
                    .map((m) => DropdownMenuItem(value: m, child: Text(m))),
                DropdownMenuItem(
                  value: _customModelSentinel,
                  child: Text(l10n.t('providerDetailCustomModelAction')),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedModel = value;
                    _isCustomModel = value == _customModelSentinel;
                  });
                }
              },
            ),
          if (_isCustomModel || _availableModels.isEmpty) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _customModelController,
              decoration: InputDecoration(
                hintText: widget.provider.modelHint(l10n),
                labelText: _availableModels.isEmpty
                    ? l10n.t('providerDetailModel')
                    : l10n.t('providerDetailCustomModelLabel'),
              ),
            ),
          ],
          const SizedBox(height: 32),

          // Actions
          if (widget.provider.supportsConnectionTest) ...[
            OutlinedButton.icon(
              onPressed: _testingConnection ? null : _testConnection,
              icon: _testingConnection
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering),
              label: Text(l10n.t('providerDetailTestConnection')),
            ),
            if (_connectionTestResult case final result?) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (result.success
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.errorContainer)
                      .withAlpha(160),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      result.success
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      size: 20,
                      color: result.success
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _connectionResultText(l10n, result),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: result.success
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(l10n.t('providerDetailSaveAction')),
          ),
          if (_isConfigured) ...[
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
    );
  }
}
