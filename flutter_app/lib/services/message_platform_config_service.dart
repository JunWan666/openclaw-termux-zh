import 'dart:convert';

import 'native_bridge.dart';
import 'preferences_service.dart';

/// Reads and writes messaging platform configuration in openclaw.json.
class MessagePlatformConfigService {
  static const _configPath = '/root/.openclaw/openclaw.json';
  static const _feishuChannelId = 'feishu';
  static const _qqbotChannelId = 'qqbot';
  static const _weixinChannelId = 'weixin';
  static const _legacyLarkChannelId = 'lark';
  static const _defaultFeishuAccountId = 'default';
  static const qqbotPluginPackage = '@tencent-connect/openclaw-qqbot@latest';
  static const qqbotConnectUrl = 'https://q.qq.com/qqbot/openclaw/login.html';
  static const weixinPluginPackage = '@tencent/openclaw-weixin';
  static const weixinInstallerCommand =
      'npx -y @tencent-weixin/openclaw-weixin-cli install';

  static String _shellEscape(String s) {
    return "'${s.replaceAll("'", "'\\''")}'";
  }

  static String _wrapOpenclawCommand(String command) {
    return '''
if [ -f /root/.openclaw/bionic-bypass.js ]; then
  export NODE_OPTIONS="--require /root/.openclaw/bionic-bypass.js"
fi
export CHOKIDAR_USEPOLLING=true
export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
export UV_USE_IO_URING=0
$command
''';
  }

  static Future<String> _runOpenclawCommand(
    String command, {
    int timeout = 120,
  }) async {
    try {
      await NativeBridge.setupDirs();
    } catch (_) {}
    try {
      await NativeBridge.writeResolv();
    } catch (_) {}

    return NativeBridge.runInProot(
      _wrapOpenclawCommand(command),
      timeout: timeout,
    );
  }

  static bool _isNonEmptyString(dynamic value) =>
      value is String && value.trim().isNotEmpty;

  static Future<PreferencesService> _loadPrefs() async {
    final prefs = PreferencesService();
    await prefs.init();
    return prefs;
  }

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

  static Future<Map<String, dynamic>?> _readQqbotLocalConfig() async {
    final prefs = await _loadPrefs();
    final appId = prefs.qqbotAppId?.trim();
    final appSecret = prefs.qqbotAppSecret?.trim();
    if ((appId == null || appId.isEmpty) &&
        (appSecret == null || appSecret.isEmpty)) {
      return null;
    }

    return {
      if (appId != null && appId.isNotEmpty) 'appId': appId,
      if (appSecret != null && appSecret.isNotEmpty) 'appSecret': appSecret,
      'configured': true,
    };
  }

  static Future<void> _saveQqbotLocalConfig({
    required String appId,
    required String appSecret,
  }) async {
    final prefs = await _loadPrefs();
    prefs.qqbotAppId = appId.trim();
    prefs.qqbotAppSecret = appSecret.trim();
  }

  static Future<void> _clearQqbotLocalConfig() async {
    final prefs = await _loadPrefs();
    prefs.qqbotAppId = null;
    prefs.qqbotAppSecret = null;
  }

  static Future<Map<String, dynamic>> readConfig() async {
    try {
      final content = await NativeBridge.readRootfsFile(_configPath);
      final platforms = <String, dynamic>{};
      if (content != null && content.isNotEmpty) {
        final config = jsonDecode(content) as Map<String, dynamic>;
        final channels = config['channels'] as Map<String, dynamic>?;
        if (channels != null) {
          for (final entry in channels.entries) {
            final key = entry.key == _legacyLarkChannelId
                ? _feishuChannelId
                : entry.key;
            final normalized = _normalizeUiConfig(
              channelId: entry.key,
              value: entry.value,
            );
            if (key == _qqbotChannelId && normalized.isEmpty) {
              platforms[key] = {'configured': true};
              continue;
            }
            if (normalized.isNotEmpty || !platforms.containsKey(key)) {
              platforms[key] = normalized;
            }
          }
        }
      }

      final qqbotLocal = await _readQqbotLocalConfig();
      if (qqbotLocal != null) {
        platforms[_qqbotChannelId] = {
          ...(platforms[_qqbotChannelId] as Map<String, dynamic>? ??
              const <String, dynamic>{}),
          ...qqbotLocal,
        };
      }

      return {'platforms': platforms};
    } catch (_) {
      final qqbotLocal = await _readQqbotLocalConfig();
      return {
        'platforms': {
          if (qqbotLocal != null) _qqbotChannelId: qqbotLocal,
        },
      };
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
    if (channelId == _qqbotChannelId) {
      await configureQqbot(
        appId: payload['appId'] as String? ?? '',
        appSecret: payload['appSecret'] as String? ?? '',
      );
      return;
    }

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
    if (channelId == _qqbotChannelId) {
      await _clearQqbotLocalConfig();
      return;
    }

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

  static Future<bool> isQqbotPluginInstalled() async {
    try {
      final output = await _runOpenclawCommand(
        'openclaw plugins list',
        timeout: 45,
      );
      final lower = output.toLowerCase();
      return lower.contains('@tencent-connect/openclaw-qqbot') ||
          lower.contains('qqbot');
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isWeixinPluginInstalled() async {
    try {
      final output = await _runOpenclawCommand(
        'openclaw plugins list',
        timeout: 45,
      );
      final lower = output.toLowerCase();
      return lower.contains('@tencent/openclaw-weixin') ||
          lower.contains('openclaw-weixin') ||
          lower.contains(_weixinChannelId);
    } catch (_) {
      return false;
    }
  }

  static Future<void> ensureQqbotPluginInstalled() async {
    final installed = await isQqbotPluginInstalled();
    if (installed) {
      return;
    }

    await _runOpenclawCommand(
      'openclaw plugins install $qqbotPluginPackage',
      timeout: 600,
    );
  }

  static Future<void> configureQqbot({
    required String appId,
    required String appSecret,
  }) async {
    final normalizedAppId = appId.trim();
    final normalizedAppSecret = appSecret.trim();
    final token = '$normalizedAppId:$normalizedAppSecret';

    await ensureQqbotPluginInstalled();
    await _runOpenclawCommand(
      'openclaw channels add --channel qqbot --token ${_shellEscape(token)}',
      timeout: 120,
    );
    await _saveQqbotLocalConfig(
      appId: normalizedAppId,
      appSecret: normalizedAppSecret,
    );
  }
}
