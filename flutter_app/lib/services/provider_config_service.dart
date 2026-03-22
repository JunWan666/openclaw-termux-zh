import 'dart:convert';
import '../models/ai_provider.dart';
import 'native_bridge.dart';

/// Reads and writes AI provider configuration in openclaw.json.
class ProviderConfigService {
  static const _configPath = '/root/.openclaw/openclaw.json';
  static const _customOpenaiId = 'custom-openai';
  static const _customOpenaiApi = 'openai-completions';
  static const _customOpenaiContextWindow = 128000;
  static const _customOpenaiMaxTokens = 8192;
  static const _localGatewayMode = 'local';

  /// Escape a string for use as a single-quoted shell argument.
  static String _shellEscape(String s) {
    return "'${s.replaceAll("'", "'\\''")}'";
  }

  static String _primaryModelForProvider(AiProvider provider, String model) {
    if (provider.id == _customOpenaiId) {
      return '${provider.id}/$model';
    }
    return model;
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
    final rawGateway = config['gateway'];
    final gateway = rawGateway is Map<String, dynamic>
        ? rawGateway
        : rawGateway is Map
            ? Map<String, dynamic>.from(rawGateway)
            : <String, dynamic>{};
    config['gateway'] = gateway;
    final mode = gateway['mode'];
    if (mode is! String || mode.trim().isEmpty) {
      gateway['mode'] = _localGatewayMode;
    }
  }

  static bool _hasSavedModelOrProviderConfig(Map<String, dynamic> config) {
    final rawModels = config['models'];
    if (rawModels is Map) {
      final providers = rawModels['providers'];
      if (providers is Map && providers.isNotEmpty) {
        return true;
      }
    }

    final rawAgents = config['agents'];
    if (rawAgents is Map) {
      final defaults = rawAgents['defaults'];
      if (defaults is Map) {
        final model = defaults['model'];
        if (model is Map) {
          final primary = model['primary'];
          if (primary is String && primary.trim().isNotEmpty) {
            return true;
          }
        }
      }
    }

    return false;
  }

  static Map<String, dynamic> _providerEntryForSave({
    required AiProvider provider,
    required String apiKey,
    required String baseUrl,
    required String model,
  }) {
    if (provider.id == _customOpenaiId) {
      return {
        'api': _customOpenaiApi,
        'apiKey': apiKey,
        'baseUrl': baseUrl,
        'models': [_customOpenaiModelEntry(model)],
      };
    }

    return {
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'models': [model],
    };
  }

  static String? _extractModelId(dynamic providerConfig) {
    if (providerConfig is! Map) return null;
    final models = providerConfig['models'];
    if (models is! List || models.isEmpty) return null;
    final first = models.first;
    if (first is String) return first;
    if (first is Map) {
      final id = first['id'];
      if (id is String && id.isNotEmpty) return id;
      final name = first['name'];
      if (name is String && name.isNotEmpty) return name;
    }
    return null;
  }

  static Future<void> migrateCustomProviderConfigIfNeeded() async {
    try {
      final content = await NativeBridge.readRootfsFile(_configPath);
      if (content == null || content.isEmpty) return;

      final config = jsonDecode(content) as Map<String, dynamic>;
      final modelsSection =
          (config['models'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
      final providers =
          (modelsSection['providers'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
      final existing =
          (providers[_customOpenaiId] as Map?)?.cast<String, dynamic>();
      if (existing == null) return;

      final modelId = _extractModelId(existing);
      if (modelId == null || modelId.isEmpty) return;

      final normalizedBaseUrl = AiProvider.customOpenai.normalizeBaseUrl(
        (existing['baseUrl'] as String?) ?? AiProvider.customOpenai.baseUrl,
      );
      final normalizedEntry = _providerEntryForSave(
        provider: AiProvider.customOpenai,
        apiKey: (existing['apiKey'] as String?) ?? '',
        baseUrl: normalizedBaseUrl,
        model: modelId,
      );

      final primaryModel =
          _primaryModelForProvider(AiProvider.customOpenai, modelId);
      final agents = (config['agents'] as Map?)?.cast<String, dynamic>();
      final defaults = (agents?['defaults'] as Map?)?.cast<String, dynamic>();
      final defaultModel =
          (defaults?['model'] as Map?)?.cast<String, dynamic>();
      final currentPrimary = defaultModel?['primary'] as String?;

      var changed = false;
      if (jsonEncode(existing) != jsonEncode(normalizedEntry)) {
        providers[_customOpenaiId] = normalizedEntry;
        modelsSection['providers'] = providers;
        config['models'] = modelsSection;
        changed = true;
      }

      if (currentPrimary == null ||
          currentPrimary == modelId ||
          currentPrimary == primaryModel) {
        config['agents'] ??= <String, dynamic>{};
        (config['agents'] as Map<String, dynamic>)['defaults'] ??=
            <String, dynamic>{};
        ((config['agents'] as Map<String, dynamic>)['defaults']
            as Map<String, dynamic>)['model'] ??= <String, dynamic>{};
        (((config['agents'] as Map<String, dynamic>)['defaults']
                as Map<String, dynamic>)['model']
            as Map<String, dynamic>)['primary'] = primaryModel;
        if (currentPrimary != primaryModel) {
          changed = true;
        }
      }

      if (!changed) return;

      await NativeBridge.writeRootfsFile(
        _configPath,
        const JsonEncoder.withIndent('  ').convert(config),
      );
    } catch (_) {
      // Non-fatal: the user can still re-save the provider manually.
    }
  }

  /// Read the current config and return a map with:
  /// - `activeModel`: the current primary model string (or null)
  /// - `providers`: `Map<providerId, {apiKey, model}>` for configured providers
  static Future<Map<String, dynamic>> readConfig() async {
    try {
      final content = await NativeBridge.readRootfsFile(_configPath);
      if (content == null || content.isEmpty) {
        return {'activeModel': null, 'providers': <String, dynamic>{}};
      }
      final config = jsonDecode(content) as Map<String, dynamic>;

      // Extract active model
      String? activeModel;
      final agents = config['agents'] as Map<String, dynamic>?;
      if (agents != null) {
        final defaults = agents['defaults'] as Map<String, dynamic>?;
        if (defaults != null) {
          final model = defaults['model'] as Map<String, dynamic>?;
          if (model != null) {
            activeModel = model['primary'] as String?;
          }
        }
      }

      // Extract configured providers
      final providers = <String, dynamic>{};
      final modelsSection = config['models'] as Map<String, dynamic>?;
      if (modelsSection != null) {
        final providerEntries =
            modelsSection['providers'] as Map<String, dynamic>?;
        if (providerEntries != null) {
          for (final entry in providerEntries.entries) {
            final value = entry.value;
            final normalized = value is Map
                ? Map<String, dynamic>.from(value)
                : <String, dynamic>{};
            normalized['model'] = _extractModelId(value);
            providers[entry.key] = normalized;
          }
        }
      }

      return {'activeModel': activeModel, 'providers': providers};
    } catch (_) {
      return {'activeModel': null, 'providers': <String, dynamic>{}};
    }
  }

  static Future<bool> hasRequiredGatewayConfig() async {
    try {
      final content = await NativeBridge.readRootfsFile(_configPath);
      if (content == null || content.isEmpty) {
        return false;
      }

      final config = jsonDecode(content) as Map<String, dynamic>;
      final rawGateway = config['gateway'];
      final gateway = rawGateway is Map<String, dynamic>
          ? rawGateway
          : rawGateway is Map
              ? Map<String, dynamic>.from(rawGateway)
              : null;
      final mode = gateway?['mode'];
      return mode is String && mode.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> ensureGatewayDefaults() async {
    Map<String, dynamic> config = {};
    try {
      final content = await NativeBridge.readRootfsFile(_configPath);
      if (content != null && content.isNotEmpty) {
        config = jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (_) {
      // Start from a fresh config if the existing file is missing or invalid.
    }

    if (!_hasSavedModelOrProviderConfig(config)) {
      return;
    }

    final before = jsonEncode(config);
    _ensureLocalGatewayMode(config);
    if (before == jsonEncode(config)) {
      return;
    }

    await NativeBridge.writeRootfsFile(
      _configPath,
      const JsonEncoder.withIndent('  ').convert(config),
    );
  }

  /// Save a provider's API key and set its model as the active model.
  /// Tries a Node.js one-liner in proot first, then falls back to a direct
  /// file write via NativeBridge.writeRootfsFile if proot/DNS is unavailable.
  static Future<void> saveProviderConfig({
    required AiProvider provider,
    required String apiKey,
    required String model,
    String? baseUrl,
  }) async {
    final rawBaseUrl = baseUrl != null && baseUrl.trim().isNotEmpty
        ? baseUrl.trim()
        : provider.baseUrl;
    final resolvedBaseUrl = provider.normalizeBaseUrl(rawBaseUrl);
    final providerJson = jsonEncode(_providerEntryForSave(
      provider: provider,
      apiKey: apiKey,
      baseUrl: resolvedBaseUrl,
      model: model,
    ));
    final primaryModelJson =
        jsonEncode(_primaryModelForProvider(provider, model));
    final providerIdJson = jsonEncode(provider.id);

    final script = '''
const fs = require("fs");
const p = "$_configPath";
let c = {};
try { c = JSON.parse(fs.readFileSync(p, "utf8")); } catch {}
if (!c.gateway) c.gateway = {};
if (!c.gateway.mode) c.gateway.mode = ${jsonEncode(_localGatewayMode)};
if (!c.models) c.models = {};
if (!c.models.providers) c.models.providers = {};
c.models.providers[$providerIdJson] = $providerJson;
if (!c.agents) c.agents = {};
if (!c.agents.defaults) c.agents.defaults = {};
if (!c.agents.defaults.model) c.agents.defaults.model = {};
c.agents.defaults.model.primary = $primaryModelJson;
fs.mkdirSync(require("path").dirname(p), { recursive: true });
fs.writeFileSync(p, JSON.stringify(c, null, 2));
''';
    try {
      await NativeBridge.runInProot(
        'node -e ${_shellEscape(script)}',
        timeout: 15,
      );
    } catch (_) {
      // Fallback: write config directly via NativeBridge file I/O
      await _saveConfigDirect(
        provider: provider,
        providerId: provider.id,
        apiKey: apiKey,
        baseUrl: resolvedBaseUrl,
        model: model,
      );
    }
  }

  /// Direct file-write fallback that doesn't depend on proot or DNS.
  static Future<void> _saveConfigDirect({
    required AiProvider provider,
    required String providerId,
    required String apiKey,
    required String baseUrl,
    required String model,
  }) async {
    Map<String, dynamic> config = {};
    try {
      final content = await NativeBridge.readRootfsFile(_configPath);
      if (content != null && content.isNotEmpty) {
        config = jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (_) {
      // Start fresh
    }

    _ensureLocalGatewayMode(config);

    // Merge provider entry
    config['models'] ??= <String, dynamic>{};
    (config['models'] as Map<String, dynamic>)['providers'] ??=
        <String, dynamic>{};
    ((config['models'] as Map<String, dynamic>)['providers']
        as Map<String, dynamic>)[providerId] = _providerEntryForSave(
      provider: provider,
      apiKey: apiKey,
      baseUrl: baseUrl,
      model: model,
    );

    // Set active model
    config['agents'] ??= <String, dynamic>{};
    (config['agents'] as Map<String, dynamic>)['defaults'] ??=
        <String, dynamic>{};
    ((config['agents'] as Map<String, dynamic>)['defaults']
        as Map<String, dynamic>)['model'] ??= <String, dynamic>{};
    (((config['agents'] as Map<String, dynamic>)['defaults']
                as Map<String, dynamic>)['model']
            as Map<String, dynamic>)['primary'] =
        _primaryModelForProvider(provider, model);

    const encoder = JsonEncoder.withIndent('  ');
    await NativeBridge.writeRootfsFile(_configPath, encoder.convert(config));
  }

  /// Remove a provider's config entry and clear the active model if it
  /// belonged to this provider.
  static Future<void> removeProviderConfig({
    required AiProvider provider,
  }) async {
    final providerIdJson = jsonEncode(provider.id);
    final modelsJson = jsonEncode(provider.defaultModels);

    final script = '''
const fs = require("fs");
const p = "$_configPath";
let c = {};
try { c = JSON.parse(fs.readFileSync(p, "utf8")); } catch {}
let known = [];
if (c.models && c.models.providers) {
  const existing = c.models.providers[$providerIdJson];
  if (existing && Array.isArray(existing.models)) {
    known = existing.models
      .map(m => typeof m === "string" ? m : (m && typeof m.id === "string" ? m.id : (m && typeof m.name === "string" ? m.name : null)))
      .filter(Boolean);
  }
  delete c.models.providers[$providerIdJson];
}
known = [...new Set([...known, ...$modelsJson])];
if (c.agents && c.agents.defaults && c.agents.defaults.model) {
  const cur = c.agents.defaults.model.primary;
  if (cur && known.some(m => cur.includes(m))) {
    delete c.agents.defaults.model.primary;
  }
}
fs.writeFileSync(p, JSON.stringify(c, null, 2));
''';
    await NativeBridge.runInProot(
      'node -e ${_shellEscape(script)}',
      timeout: 15,
    );
  }
}
