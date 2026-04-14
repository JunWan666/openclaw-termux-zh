import 'dart:convert';

import '../models/ai_provider.dart';
import '../models/custom_provider_preset.dart';
import 'native_bridge.dart';
import 'preferences_service.dart';

/// Reads and writes AI provider configuration in openclaw.json.
class ProviderConfigService {
  static const _configPath = '/root/.openclaw/openclaw.json';
  static const _customPresetMetadataPath =
      '/root/.openclaw/app/custom-provider-presets.json';
  static const _customOpenaiId = 'custom-openai';
  static const _customOpenaiContextWindow = 128000;
  static const _customOpenaiMaxTokens = 8192;
  static const _localGatewayMode = 'local';

  static final Set<String> _builtInProviderIds = {
    for (final provider in AiProvider.all.where(
      (provider) => provider.id != _customOpenaiId,
    ))
      provider.id,
  };

  static bool _isNonEmptyString(dynamic value) =>
      value is String && value.trim().isNotEmpty;

  static Map<String, dynamic> _asStringKeyedMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), item),
      );
    }
    return <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> _readConfigMap() async {
    try {
      final content = await NativeBridge.readRootfsFile(_configPath);
      if (content == null || content.isEmpty) {
        return <String, dynamic>{};
      }
      return _asStringKeyedMap(jsonDecode(content));
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Future<void> _writeConfigMap(Map<String, dynamic> config) async {
    await NativeBridge.writeRootfsFile(
      _configPath,
      const JsonEncoder.withIndent('  ').convert(config),
    );
  }

  static Future<Map<String, dynamic>> _readCustomPresetMetadataMap() async {
    try {
      final content =
          await NativeBridge.readRootfsFile(_customPresetMetadataPath);
      if (content == null || content.trim().isEmpty) {
        return <String, dynamic>{};
      }
      return _asStringKeyedMap(jsonDecode(content));
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Future<void> _writeCustomPresetMetadataMap(
    Map<String, dynamic> metadata,
  ) async {
    final presets = _ensureCustomPresetMetadataEntries(metadata);
    metadata['presets'] = presets;
    await NativeBridge.writeRootfsFile(
      _customPresetMetadataPath,
      const JsonEncoder.withIndent('  ').convert(metadata),
    );
  }

  static Map<String, dynamic> _ensureGatewaySection(
      Map<String, dynamic> config) {
    final gateway = _asStringKeyedMap(config['gateway']);
    config['gateway'] = gateway;
    return gateway;
  }

  static Map<String, dynamic> _ensureDiscoverySection(
    Map<String, dynamic> config,
  ) {
    final discovery = _asStringKeyedMap(config['discovery']);
    config['discovery'] = discovery;
    return discovery;
  }

  static Map<String, dynamic> _ensureMdnsSection(
    Map<String, dynamic> config,
  ) {
    final discovery = _ensureDiscoverySection(config);
    final mdns = _asStringKeyedMap(discovery['mdns']);
    discovery['mdns'] = mdns;
    return mdns;
  }

  static Map<String, dynamic> _ensureGatewayReloadSection(
    Map<String, dynamic> config,
  ) {
    final gateway = _ensureGatewaySection(config);
    final reload = _asStringKeyedMap(gateway['reload']);
    gateway['reload'] = reload;
    return reload;
  }

  static Map<String, dynamic> _ensureModelsSection(
      Map<String, dynamic> config) {
    final models = _asStringKeyedMap(config['models']);
    config['models'] = models;
    return models;
  }

  static Map<String, dynamic> _ensureProvidersSection(
    Map<String, dynamic> config,
  ) {
    final models = _ensureModelsSection(config);
    final providers = _asStringKeyedMap(models['providers']);
    models['providers'] = providers;
    return providers;
  }

  static Map<String, dynamic> _ensureAgentsSection(
      Map<String, dynamic> config) {
    final agents = _asStringKeyedMap(config['agents']);
    config['agents'] = agents;
    return agents;
  }

  static Map<String, dynamic> _ensureDefaultsSection(
    Map<String, dynamic> config,
  ) {
    final agents = _ensureAgentsSection(config);
    final defaults = _asStringKeyedMap(agents['defaults']);
    agents['defaults'] = defaults;
    return defaults;
  }

  static Map<String, dynamic> _ensureDefaultModelSection(
    Map<String, dynamic> config,
  ) {
    final defaults = _ensureDefaultsSection(config);
    final model = _asStringKeyedMap(defaults['model']);
    defaults['model'] = model;
    return model;
  }

  static Map<String, dynamic>? _defaultModelsAllowList(
    Map<String, dynamic> config,
  ) {
    final agents = config['agents'];
    if (agents is! Map) return null;
    final defaults = agents['defaults'];
    if (defaults is! Map) return null;
    final models = defaults['models'];
    if (models is Map<String, dynamic>) return models;
    if (models is Map) {
      final casted = _asStringKeyedMap(models);
      defaults['models'] = casted;
      return casted;
    }
    return null;
  }

  static Map<String, dynamic> _ensureCustomPresetMetadataEntries(
    Map<String, dynamic> metadata,
  ) {
    final presets = _asStringKeyedMap(metadata['presets']);
    metadata['presets'] = presets;
    return presets;
  }

  static Map<String, dynamic> _customPresetMetadataEntry(
    Map<String, dynamic>? metadata,
    String providerId,
  ) {
    if (metadata == null) {
      return <String, dynamic>{};
    }
    final presets = _asStringKeyedMap(metadata['presets']);
    return _asStringKeyedMap(presets[providerId]);
  }

  static bool _setCustomPresetAlias(
    Map<String, dynamic> metadata, {
    required String providerId,
    required String alias,
  }) {
    final presets = _ensureCustomPresetMetadataEntries(metadata);
    final trimmedAlias = alias.trim();
    final existingEntry = _asStringKeyedMap(presets[providerId]);
    final currentAlias = (existingEntry['alias'] as String? ?? '').trim();

    if (trimmedAlias.isEmpty) {
      if (existingEntry.isEmpty) {
        return false;
      }
      existingEntry.remove('alias');
      if (existingEntry.isEmpty) {
        presets.remove(providerId);
      } else {
        presets[providerId] = existingEntry;
      }
      return currentAlias.isNotEmpty || !presets.containsKey(providerId);
    }

    if (currentAlias == trimmedAlias) {
      return false;
    }

    existingEntry['alias'] = trimmedAlias;
    presets[providerId] = existingEntry;
    return true;
  }

  static bool _removeCustomPresetMetadataEntry(
    Map<String, dynamic> metadata, {
    required String providerId,
  }) {
    final presets = _ensureCustomPresetMetadataEntries(metadata);
    return presets.remove(providerId) != null;
  }

  static String? _readActiveModel(Map<String, dynamic> config) {
    final agents = config['agents'];
    if (agents is! Map) return null;
    final defaults = agents['defaults'];
    if (defaults is! Map) return null;
    final model = defaults['model'];
    if (model is! Map) return null;
    final primary = model['primary'];
    return primary is String ? primary : null;
  }

  static String _primaryModelForProvider(
    AiProvider provider,
    String model, {
    String? customProviderId,
  }) {
    if (provider.id == _customOpenaiId) {
      final providerId = _isNonEmptyString(customProviderId)
          ? customProviderId!.trim()
          : provider.id;
      return '$providerId/$model';
    }
    return model;
  }

  static String? providerIdFromModelRef(String? modelRef) {
    if (modelRef == null) return null;
    final trimmed = modelRef.trim();
    if (trimmed.isEmpty) return null;
    final separatorIndex = trimmed.indexOf('/');
    if (separatorIndex <= 0) return null;
    return trimmed.substring(0, separatorIndex);
  }

  static Map<String, dynamic> _customOpenaiModelEntry(String model) => {
        'id': model,
        'name': model,
        'input': const ['text'],
        'reasoning': false,
        'contextWindow': _customOpenaiContextWindow,
        'maxTokens': _customOpenaiMaxTokens,
        'cost': const {
          'input': 0,
          'output': 0,
          'cacheRead': 0,
          'cacheWrite': 0,
        },
      };

  static void _ensureLocalGatewayMode(Map<String, dynamic> config) {
    final gateway = _ensureGatewaySection(config);
    final mode = gateway['mode'];
    if (mode is! String || mode.trim().isEmpty) {
      gateway['mode'] = _localGatewayMode;
    }
  }

  static void _setBonjourMode(
    Map<String, dynamic> config, {
    required bool enabled,
  }) {
    final mdns = _ensureMdnsSection(config);
    mdns['mode'] = enabled ? 'minimal' : 'off';
  }

  static bool? _bonjourEnabledFromConfig(Map<String, dynamic> config) {
    final discovery = config['discovery'];
    if (discovery is! Map) {
      return null;
    }
    final mdns = discovery['mdns'];
    if (mdns is! Map) {
      return null;
    }
    final mode = mdns['mode'];
    if (mode is! String || mode.trim().isEmpty) {
      return null;
    }
    return mode.trim().toLowerCase() != 'off';
  }

  static bool _hasSavedModelOrProviderConfig(Map<String, dynamic> config) {
    final providers = _ensureProvidersSection(config);
    if (providers.isNotEmpty) {
      return true;
    }

    final primary = _readActiveModel(config);
    return _isNonEmptyString(primary);
  }

  static Map<String, dynamic> _providerEntryForSave({
    required AiProvider provider,
    required String apiKey,
    required String baseUrl,
    required String model,
  }) {
    final entry = <String, dynamic>{
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'models': [model],
    };
    if (_isNonEmptyString(provider.apiValue)) {
      entry['api'] = provider.apiValue;
    }
    return entry;
  }

  static String? _extractModelId(dynamic providerConfig) {
    if (providerConfig is! Map) return null;
    final models = providerConfig['models'];
    if (models is! List || models.isEmpty) return null;
    final first = models.first;
    if (first is String) {
      return first.trim().isEmpty ? null : first.trim();
    }
    if (first is Map) {
      final id = first['id'];
      if (_isNonEmptyString(id)) {
        return (id as String).trim();
      }
      final name = first['name'];
      if (_isNonEmptyString(name)) {
        return (name as String).trim();
      }
    }
    return null;
  }

  static String normalizeCustomBaseUrl(
    String input,
    CustomProviderCompatibility compatibility,
  ) {
    final trimmed = input.trim();
    if (trimmed.isEmpty || !compatibility.appendsV1) {
      return trimmed;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return trimmed;
    }

    var path = uri.path.trim();
    if (path.isEmpty || path == '/') {
      path = '/v1';
    } else {
      path = path.replaceAll(RegExp(r'/+$'), '');
      const suffixes = [
        '/chat/completions',
        '/responses',
      ];
      for (final suffix in suffixes) {
        if (path.endsWith(suffix)) {
          path = path.substring(0, path.length - suffix.length);
          break;
        }
      }
      if (path.isEmpty || path == '/') {
        path = '/v1';
      } else if (!path.endsWith('/v1')) {
        path = '$path/v1';
      }
    }

    return uri.replace(path: path).toString();
  }

  static String _sanitizeProviderId(String input) {
    return input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  }

  static String _defaultProviderIdBase(
    CustomProviderCompatibility compatibility,
  ) {
    switch (compatibility) {
      case CustomProviderCompatibility.autoDetect:
      case CustomProviderCompatibility.openaiChatCompletions:
        return 'custom-openai';
      case CustomProviderCompatibility.zhipuChatCompletions:
        return 'custom-zhipu';
      case CustomProviderCompatibility.openaiResponses:
        return 'custom-openai-responses';
      case CustomProviderCompatibility.anthropicMessages:
        return 'custom-anthropic';
      case CustomProviderCompatibility.googleGenerativeAi:
        return 'custom-google';
    }
  }

  static String _nextAvailableProviderId({
    required String baseId,
    required Iterable<String> existingProviderIds,
    String? currentProviderId,
  }) {
    if (baseId == currentProviderId || !existingProviderIds.contains(baseId)) {
      return baseId;
    }

    var index = 2;
    while (true) {
      final candidate = '$baseId-$index';
      if (candidate == currentProviderId ||
          !existingProviderIds.contains(candidate)) {
        return candidate;
      }
      index += 1;
    }
  }

  static String _resolveCustomProviderId({
    required CustomProviderCompatibility compatibility,
    required Iterable<String> existingProviderIds,
    String? requestedProviderId,
    String? previousProviderId,
  }) {
    final sanitizedRequested = requestedProviderId == null
        ? ''
        : _sanitizeProviderId(requestedProviderId);
    if (sanitizedRequested.isNotEmpty) {
      if (sanitizedRequested != previousProviderId &&
          existingProviderIds.contains(sanitizedRequested)) {
        throw Exception('Provider ID already exists: $sanitizedRequested');
      }
      return sanitizedRequested;
    }

    if (_isNonEmptyString(previousProviderId)) {
      return previousProviderId!.trim();
    }

    final baseId = _defaultProviderIdBase(compatibility);
    return _nextAvailableProviderId(
      baseId: baseId,
      existingProviderIds: existingProviderIds,
      currentProviderId: previousProviderId,
    );
  }

  static CustomProviderPreset? _customPresetFromEntry({
    required String providerId,
    required dynamic rawProviderConfig,
    Map<String, dynamic>? allowList,
    Map<String, dynamic>? presetMetadata,
  }) {
    if (_builtInProviderIds.contains(providerId)) {
      return null;
    }

    final providerConfig = _asStringKeyedMap(rawProviderConfig);
    final modelId = _extractModelId(providerConfig);
    final baseUrl = providerConfig['baseUrl'] as String?;
    if (!_isNonEmptyString(modelId) || !_isNonEmptyString(baseUrl)) {
      return null;
    }

    final modelRef = '$providerId/${modelId!.trim()}';
    final allowListEntry = allowList == null
        ? const <String, dynamic>{}
        : _asStringKeyedMap(allowList[modelRef]);
    final presetMetadataEntry =
        _customPresetMetadataEntry(presetMetadata, providerId);
    final alias = (presetMetadataEntry['alias'] as String? ??
            providerConfig['alias'] as String? ??
            allowListEntry['alias'] as String? ??
            '')
        .trim();

    return CustomProviderPreset(
      providerId: providerId,
      modelId: modelId,
      baseUrl: baseUrl!.trim(),
      apiKey: (providerConfig['apiKey'] as String? ?? '').trim(),
      alias: alias,
      compatibility: CustomProviderCompatibility.resolveSavedCompatibility(
        apiValue: providerConfig['api'] as String?,
        baseUrl: baseUrl,
      ),
    );
  }

  static bool _clearLegacyAliasInAllowList(
    Map<String, dynamic> config, {
    required String modelRef,
  }) {
    final allowList = _defaultModelsAllowList(config);
    if (allowList == null) {
      return false;
    }

    if (!allowList.containsKey(modelRef)) {
      return false;
    }

    final existingEntry = _asStringKeyedMap(allowList[modelRef]);
    final removedAlias = existingEntry.remove('alias') != null;
    if (existingEntry.isEmpty) {
      allowList.remove(modelRef);
    } else {
      allowList[modelRef] = existingEntry;
    }
    return removedAlias;
  }

  static Future<void> migrateCustomProviderConfigIfNeeded() async {
    try {
      final config = await _readConfigMap();
      final presetMetadata = await _readCustomPresetMetadataMap();
      final providers = _ensureProvidersSection(config);
      final activeModel = _readActiveModel(config);
      final allowList = _defaultModelsAllowList(config);
      final knownCustomProviderIds = <String>{};
      var configChanged = false;
      var metadataChanged = false;

      for (final entry in providers.entries.toList()) {
        final preset = _customPresetFromEntry(
          providerId: entry.key,
          rawProviderConfig: entry.value,
          allowList: allowList,
          presetMetadata: presetMetadata,
        );
        if (preset == null) {
          continue;
        }
        knownCustomProviderIds.add(entry.key);

        final normalizedBaseUrl = normalizeCustomBaseUrl(
          preset.baseUrl,
          preset.compatibility,
        );
        final providerConfig = _asStringKeyedMap(entry.value);
        if (normalizedBaseUrl != preset.baseUrl) {
          providerConfig['baseUrl'] = normalizedBaseUrl;
          providers[entry.key] = providerConfig;
          configChanged = true;
        }

        final normalizedPrimary = preset.modelRef;
        if (activeModel == preset.modelId) {
          _ensureDefaultModelSection(config)['primary'] = normalizedPrimary;
          configChanged = true;
        }

        if (providerConfig.containsKey('alias')) {
          providerConfig.remove('alias');
          providers[entry.key] = providerConfig;
          configChanged = true;
        }

        if (_clearLegacyAliasInAllowList(config, modelRef: normalizedPrimary)) {
          configChanged = true;
        }

        if (_setCustomPresetAlias(
          presetMetadata,
          providerId: entry.key,
          alias: preset.alias,
        )) {
          metadataChanged = true;
        }
      }

      final presetEntries =
          _ensureCustomPresetMetadataEntries(presetMetadata).keys.toList();
      for (final providerId in presetEntries) {
        if (!knownCustomProviderIds.contains(providerId)) {
          if (_removeCustomPresetMetadataEntry(
            presetMetadata,
            providerId: providerId,
          )) {
            metadataChanged = true;
          }
        }
      }

      if (configChanged) {
        await _writeConfigMap(config);
      }

      if (metadataChanged) {
        await _writeCustomPresetMetadataMap(presetMetadata);
      }
    } catch (_) {
      // Non-fatal: the user can still re-save the provider manually.
    }
  }

  /// Read the current config and return a map with:
  /// - `activeModel`: the current primary model string (or null)
  /// - `providers`: `Map<providerId, {apiKey, model}>` for configured providers
  /// - `customPresets`: `List<CustomProviderPreset>` for custom endpoints
  static Future<Map<String, dynamic>> readConfig() async {
    try {
      final config = await _readConfigMap();
      final presetMetadata = await _readCustomPresetMetadataMap();
      final activeModel = _readActiveModel(config);
      final providers = <String, dynamic>{};
      final customPresets = <CustomProviderPreset>[];

      final modelsSection = _asStringKeyedMap(config['models']);
      final providerEntries = _asStringKeyedMap(modelsSection['providers']);
      final allowList = _defaultModelsAllowList(config);

      for (final entry in providerEntries.entries) {
        final normalized = _asStringKeyedMap(entry.value);
        normalized['model'] = _extractModelId(entry.value);
        providers[entry.key] = normalized;

        final preset = _customPresetFromEntry(
          providerId: entry.key,
          rawProviderConfig: entry.value,
          allowList: allowList,
          presetMetadata: presetMetadata,
        );
        if (preset != null) {
          customPresets.add(preset);
        }
      }

      customPresets.sort((left, right) {
        final leftLabel = left.displayName.toLowerCase();
        final rightLabel = right.displayName.toLowerCase();
        final labelCompare = leftLabel.compareTo(rightLabel);
        if (labelCompare != 0) {
          return labelCompare;
        }
        return left.providerId.compareTo(right.providerId);
      });

      return {
        'activeModel': activeModel,
        'providers': providers,
        'customPresets': customPresets,
      };
    } catch (_) {
      return {
        'activeModel': null,
        'providers': <String, dynamic>{},
        'customPresets': const <CustomProviderPreset>[],
      };
    }
  }

  static Future<bool> hasRequiredGatewayConfig() async {
    try {
      final config = await _readConfigMap();
      final gateway = _asStringKeyedMap(config['gateway']);
      final mode = gateway['mode'];
      return mode is String && mode.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> ensureGatewayDefaults() async {
    final config = await _readConfigMap();
    final before = jsonEncode(config);

    final prefs = PreferencesService();
    await prefs.init();
    _setBonjourMode(config, enabled: prefs.bonjourEnabled);

    if (_hasSavedModelOrProviderConfig(config)) {
      _ensureLocalGatewayMode(config);
      final reload = _ensureGatewayReloadSection(config);
      final mode = reload['mode'];
      if (mode is! String || mode.trim().isEmpty) {
        reload['mode'] = 'hybrid';
      }
    }
    if (before == jsonEncode(config)) {
      return;
    }

    await _writeConfigMap(config);
  }

  static Future<bool> readBonjourEnabled() async {
    try {
      final config = await _readConfigMap();
      final configValue = _bonjourEnabledFromConfig(config);
      if (configValue != null) {
        return configValue;
      }
    } catch (_) {
      // Fall back to preferences below.
    }

    final prefs = PreferencesService();
    await prefs.init();
    return prefs.bonjourEnabled;
  }

  static Future<void> setBonjourEnabled(bool enabled) async {
    final config = await _readConfigMap();
    final before = jsonEncode(config);
    _setBonjourMode(config, enabled: enabled);
    if (before == jsonEncode(config)) {
      return;
    }
    await _writeConfigMap(config);
  }

  /// Save a provider's API key and set its model as the active model.
  static Future<void> saveProviderConfig({
    required AiProvider provider,
    required String apiKey,
    required String model,
    String? baseUrl,
  }) async {
    final rawBaseUrl =
        _isNonEmptyString(baseUrl) ? baseUrl!.trim() : provider.baseUrl;
    final resolvedBaseUrl = provider.normalizeBaseUrl(rawBaseUrl);

    final config = await _readConfigMap();
    _ensureLocalGatewayMode(config);

    final providers = _ensureProvidersSection(config);
    providers[provider.id] = _providerEntryForSave(
      provider: provider,
      apiKey: apiKey,
      baseUrl: resolvedBaseUrl,
      model: model,
    );

    _ensureDefaultModelSection(config)['primary'] =
        _primaryModelForProvider(provider, model);
    await _writeConfigMap(config);
  }

  static Map<String, dynamic> _buildCustomProviderEntry({
    required dynamic existingValue,
    required CustomProviderCompatibility compatibility,
    required String apiKey,
    required String baseUrl,
    required String modelId,
  }) {
    final providerEntry = _asStringKeyedMap(existingValue);
    if (compatibility.apiValue != null) {
      providerEntry['api'] = compatibility.apiValue;
    } else {
      providerEntry.remove('api');
    }
    providerEntry['apiKey'] = apiKey;
    providerEntry['baseUrl'] = baseUrl;
    providerEntry.remove('alias');

    final rawModels = providerEntry['models'];
    final modelTemplate =
        rawModels is List && rawModels.isNotEmpty && rawModels.first is Map
            ? _asStringKeyedMap(rawModels.first)
            : _customOpenaiModelEntry(modelId);
    modelTemplate['id'] = modelId;
    modelTemplate['name'] = modelId;
    modelTemplate['input'] ??= const ['text'];
    modelTemplate['reasoning'] ??= false;
    modelTemplate['contextWindow'] ??= _customOpenaiContextWindow;
    modelTemplate['maxTokens'] ??= _customOpenaiMaxTokens;
    modelTemplate['cost'] ??= const {
      'input': 0,
      'output': 0,
      'cacheRead': 0,
      'cacheWrite': 0,
    };
    providerEntry['models'] = [modelTemplate];
    return providerEntry;
  }

  static Future<CustomProviderPreset> saveCustomProviderPreset({
    required CustomProviderCompatibility compatibility,
    required String apiKey,
    required String baseUrl,
    required String modelId,
    String? providerId,
    String alias = '',
    String? previousProviderId,
  }) async {
    final config = await _readConfigMap();
    final presetMetadata = await _readCustomPresetMetadataMap();
    _ensureLocalGatewayMode(config);

    final providers = _ensureProvidersSection(config);
    final resolvedProviderId = _resolveCustomProviderId(
      compatibility: compatibility,
      existingProviderIds: providers.keys,
      requestedProviderId: providerId,
      previousProviderId: previousProviderId,
    );
    final resolvedBaseUrl = normalizeCustomBaseUrl(baseUrl, compatibility);
    final trimmedAlias = alias.trim();
    final trimmedModelId = modelId.trim();
    final previousProviderConfig =
        previousProviderId == null ? null : providers[previousProviderId];
    final previousModelId = _extractModelId(previousProviderConfig);

    if (previousProviderId != null &&
        previousProviderId != resolvedProviderId) {
      providers.remove(previousProviderId);
      if (_isNonEmptyString(previousModelId)) {
        _clearLegacyAliasInAllowList(
          config,
          modelRef: '$previousProviderId/${previousModelId!.trim()}',
        );
      }
      _removeCustomPresetMetadataEntry(
        presetMetadata,
        providerId: previousProviderId,
      );
    } else if (_isNonEmptyString(previousModelId) &&
        previousModelId != trimmedModelId) {
      _clearLegacyAliasInAllowList(
        config,
        modelRef: '$resolvedProviderId/${previousModelId!.trim()}',
      );
    }

    providers[resolvedProviderId] = _buildCustomProviderEntry(
      existingValue: previousProviderConfig ?? providers[resolvedProviderId],
      compatibility: compatibility,
      apiKey: apiKey.trim(),
      baseUrl: resolvedBaseUrl,
      modelId: trimmedModelId,
    );

    final modelRef = '$resolvedProviderId/$trimmedModelId';
    _ensureDefaultModelSection(config)['primary'] = modelRef;
    _clearLegacyAliasInAllowList(config, modelRef: modelRef);
    _setCustomPresetAlias(
      presetMetadata,
      providerId: resolvedProviderId,
      alias: trimmedAlias,
    );

    await _writeConfigMap(config);
    await _writeCustomPresetMetadataMap(presetMetadata);
    return CustomProviderPreset(
      providerId: resolvedProviderId,
      modelId: trimmedModelId,
      baseUrl: resolvedBaseUrl,
      apiKey: apiKey.trim(),
      alias: trimmedAlias,
      compatibility: compatibility,
    );
  }

  static Future<void> activateModel(String modelRef) async {
    final trimmed = modelRef.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final config = await _readConfigMap();
    _ensureLocalGatewayMode(config);
    _ensureDefaultModelSection(config)['primary'] = trimmed;
    await _writeConfigMap(config);
  }

  /// Remove a provider's config entry and clear the active model if it
  /// belonged to this provider.
  static Future<void> removeProviderConfig({
    required AiProvider provider,
  }) async {
    final config = await _readConfigMap();
    final providers = _ensureProvidersSection(config);
    final existing = _asStringKeyedMap(providers[provider.id]);
    final knownModels = <String>{...provider.defaultModels};
    final existingModelId = _extractModelId(existing);
    if (_isNonEmptyString(existingModelId)) {
      knownModels.add(existingModelId!);
    }

    providers.remove(provider.id);

    final activeModel = _readActiveModel(config);
    if (_isNonEmptyString(activeModel) &&
        knownModels.any((model) => activeModel!.contains(model))) {
      _ensureDefaultModelSection(config).remove('primary');
    }

    await _writeConfigMap(config);
  }

  static Future<void> removeCustomProviderPreset({
    required String providerId,
  }) async {
    final config = await _readConfigMap();
    final presetMetadata = await _readCustomPresetMetadataMap();
    final providers = _ensureProvidersSection(config);
    final existing = _asStringKeyedMap(providers[providerId]);
    final modelId = _extractModelId(existing);

    providers.remove(providerId);
    _removeCustomPresetMetadataEntry(
      presetMetadata,
      providerId: providerId,
    );

    if (_isNonEmptyString(modelId)) {
      final modelRef = '$providerId/${modelId!.trim()}';
      _clearLegacyAliasInAllowList(config, modelRef: modelRef);

      final activeModel = _readActiveModel(config);
      if (activeModel == modelRef || activeModel == modelId) {
        _ensureDefaultModelSection(config).remove('primary');
      }
    }

    await _writeConfigMap(config);
    await _writeCustomPresetMetadataMap(presetMetadata);
  }
}
