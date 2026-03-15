import 'dart:convert';

import 'native_bridge.dart';

/// Reads and writes messaging platform configuration in openclaw.json.
class MessagePlatformConfigService {
  static const _configPath = '/root/.openclaw/openclaw.json';
  static const _feishuChannelId = 'feishu';
  static const _legacyLarkChannelId = 'lark';
  static const _defaultFeishuAccountId = 'default';

  static String _shellEscape(String s) {
    return "'${s.replaceAll("'", "'\\''")}'";
  }

  static bool _isNonEmptyString(dynamic value) =>
      value is String && value.trim().isNotEmpty;

  static Map<String, dynamic>? _extractFeishuUiConfig(dynamic raw) {
    if (raw is! Map) return null;
    final channel = Map<String, dynamic>.from(raw);

    String? appId;
    String? appSecret;
    String? botName;
    String? domain;

    final accounts = channel['accounts'];
    if (accounts is Map && accounts.isNotEmpty) {
      final accountMap = Map<String, dynamic>.from(accounts);
      final preferredAccountId = (channel['defaultAccount'] as String?) ??
          (accountMap.containsKey(_defaultFeishuAccountId)
              ? _defaultFeishuAccountId
              : accountMap.keys.first);
      final account = accountMap[preferredAccountId];
      if (account is Map) {
        final normalizedAccount = Map<String, dynamic>.from(account);
        appId = normalizedAccount['appId'] as String?;
        appSecret = normalizedAccount['appSecret'] as String?;
        botName = normalizedAccount['botName'] as String?;
        domain = normalizedAccount['domain'] as String?;
      }
    }

    appId ??= channel['appId'] as String?;
    appSecret ??= channel['appSecret'] as String?;
    botName ??= channel['botName'] as String?;
    domain ??= channel['domain'] as String?;

    if (!_isNonEmptyString(appId) && !_isNonEmptyString(appSecret)) {
      return null;
    }

    return {
      if (_isNonEmptyString(appId)) 'appId': appId!.trim(),
      if (_isNonEmptyString(appSecret)) 'appSecret': appSecret!.trim(),
      if (_isNonEmptyString(botName)) 'botName': botName!.trim(),
      'domain': _isNonEmptyString(domain) ? domain!.trim() : 'feishu',
    };
  }

  static Map<String, dynamic> _buildFeishuStoredConfig(
    Map<String, dynamic> payload,
  ) {
    final appId = (payload['appId'] as String? ?? '').trim();
    final appSecret = (payload['appSecret'] as String? ?? '').trim();
    final botName = (payload['botName'] as String? ?? '').trim();
    final domain = (payload['domain'] as String? ?? 'feishu').trim();

    return {
      'enabled': true,
      'dmPolicy': 'pairing',
      'defaultAccount': _defaultFeishuAccountId,
      if (domain.isNotEmpty) 'domain': domain,
      'accounts': {
        _defaultFeishuAccountId: {
          'appId': appId,
          'appSecret': appSecret,
          if (botName.isNotEmpty) 'botName': botName,
        },
      },
    };
  }

  static Map<String, dynamic> _normalizeUiConfig({
    required String channelId,
    required dynamic value,
  }) {
    if (channelId == _feishuChannelId || channelId == _legacyLarkChannelId) {
      return _extractFeishuUiConfig(value) ?? <String, dynamic>{};
    }
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  static Map<String, dynamic> _storagePayloadForSave({
    required String channelId,
    required Map<String, dynamic> payload,
  }) {
    if (channelId == _feishuChannelId) {
      return _buildFeishuStoredConfig(payload);
    }
    return payload;
  }

  static Future<Map<String, dynamic>> readConfig() async {
    try {
      final content = await NativeBridge.readRootfsFile(_configPath);
      if (content == null || content.isEmpty) {
        return {'platforms': <String, dynamic>{}};
      }

      final config = jsonDecode(content) as Map<String, dynamic>;
      final platforms = <String, dynamic>{};
      final channels = config['channels'] as Map<String, dynamic>?;
      if (channels != null) {
        for (final entry in channels.entries) {
          final key =
              entry.key == _legacyLarkChannelId ? _feishuChannelId : entry.key;
          final normalized = _normalizeUiConfig(
            channelId: entry.key,
            value: entry.value,
          );
          if (normalized.isNotEmpty || !platforms.containsKey(key)) {
            platforms[key] = normalized;
          }
        }
      }
      return {'platforms': platforms};
    } catch (_) {
      return {'platforms': <String, dynamic>{}};
    }
  }

  static Future<void> migrateFeishuConfigIfNeeded() async {
    try {
      final content = await NativeBridge.readRootfsFile(_configPath);
      if (content == null || content.isEmpty) return;

      final config = jsonDecode(content) as Map<String, dynamic>;
      final channels = (config['channels'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};

      final existingFeishu = channels[_feishuChannelId];
      final legacyLark = channels[_legacyLarkChannelId];
      final normalized = _extractFeishuUiConfig(existingFeishu) ??
          _extractFeishuUiConfig(legacyLark);

      var changed = false;
      if (normalized != null) {
        final canonical = _buildFeishuStoredConfig(normalized);
        if (jsonEncode(existingFeishu) != jsonEncode(canonical)) {
          channels[_feishuChannelId] = canonical;
          changed = true;
        }
      }

      if (channels.remove(_legacyLarkChannelId) != null) {
        changed = true;
      }

      if (!changed) return;

      config['channels'] = channels;
      await NativeBridge.writeRootfsFile(
        _configPath,
        const JsonEncoder.withIndent('  ').convert(config),
      );
    } catch (_) {
      // Non-fatal: the user can still re-save the channel manually.
    }
  }

  static Future<void> saveChannelConfig({
    required String channelId,
    required Map<String, dynamic> payload,
  }) async {
    final channelIdJson = jsonEncode(channelId);
    final storedPayload = _storagePayloadForSave(
      channelId: channelId,
      payload: payload,
    );
    final payloadJson = jsonEncode(storedPayload);
    final cleanupLegacy = channelId == _feishuChannelId
        ? 'delete c.channels["$_legacyLarkChannelId"];'
        : '';

    final script = '''
const fs = require("fs");
const p = "$_configPath";
let c = {};
try { c = JSON.parse(fs.readFileSync(p, "utf8")); } catch {}
if (!c.channels) c.channels = {};
c.channels[$channelIdJson] = $payloadJson;
$cleanupLegacy
fs.mkdirSync(require("path").dirname(p), { recursive: true });
fs.writeFileSync(p, JSON.stringify(c, null, 2));
''';

    try {
      await NativeBridge.runInProot(
        'node -e ${_shellEscape(script)}',
        timeout: 15,
      );
    } catch (_) {
      await _saveChannelConfigDirect(
        channelId: channelId,
        payload: storedPayload,
      );
    }
  }

  static Future<void> _saveChannelConfigDirect({
    required String channelId,
    required Map<String, dynamic> payload,
  }) async {
    Map<String, dynamic> config = {};
    try {
      final content = await NativeBridge.readRootfsFile(_configPath);
      if (content != null && content.isNotEmpty) {
        config = jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (_) {
      // Start fresh if config is missing or invalid.
    }

    config['channels'] ??= <String, dynamic>{};
    (config['channels'] as Map<String, dynamic>)[channelId] = payload;
    if (channelId == _feishuChannelId) {
      (config['channels'] as Map<String, dynamic>).remove(_legacyLarkChannelId);
    }

    const encoder = JsonEncoder.withIndent('  ');
    await NativeBridge.writeRootfsFile(_configPath, encoder.convert(config));
  }

  static Future<void> removeChannelConfig({
    required String channelId,
  }) async {
    final channelIdJson = jsonEncode(channelId);

    final script = '''
const fs = require("fs");
const p = "$_configPath";
let c = {};
try { c = JSON.parse(fs.readFileSync(p, "utf8")); } catch {}
if (c.channels) {
  delete c.channels[$channelIdJson];
}
fs.mkdirSync(require("path").dirname(p), { recursive: true });
fs.writeFileSync(p, JSON.stringify(c, null, 2));
''';

    try {
      await NativeBridge.runInProot(
        'node -e ${_shellEscape(script)}',
        timeout: 15,
      );
    } catch (_) {
      await _removeChannelConfigDirect(channelId: channelId);
    }
  }

  static Future<void> _removeChannelConfigDirect({
    required String channelId,
  }) async {
    Map<String, dynamic> config = {};
    try {
      final content = await NativeBridge.readRootfsFile(_configPath);
      if (content != null && content.isNotEmpty) {
        config = jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (_) {
      // Nothing to remove if config is missing or invalid.
    }

    final channels = config['channels'] as Map<String, dynamic>?;
    channels?.remove(channelId);

    const encoder = JsonEncoder.withIndent('  ');
    await NativeBridge.writeRootfsFile(_configPath, encoder.convert(config));
  }
}
