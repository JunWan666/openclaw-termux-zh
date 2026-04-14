import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/constants.dart';
import 'package:openclaw/models/custom_provider_preset.dart';
import 'package:openclaw/services/provider_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const configPath = '/root/.openclaw/openclaw.json';
  const metadataPath = '/root/.openclaw/app/custom-provider-presets.json';
  const channel = MethodChannel(AppConstants.channelName);

  late Map<String, String> rootfsFiles;

  setUp(() {
    rootfsFiles = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final arguments = Map<String, dynamic>.from(
        call.arguments as Map? ?? const <String, dynamic>{},
      );
      switch (call.method) {
        case 'readRootfsFile':
          return rootfsFiles[arguments['path'] as String];
        case 'writeRootfsFile':
          rootfsFiles[arguments['path'] as String] =
              arguments['content'] as String;
          return true;
        default:
          throw MissingPluginException('Unhandled method: ${call.method}');
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('ProviderConfigService.normalizeCustomBaseUrl', () {
    test('keeps Zhipu base URL without appending v1', () {
      expect(
        ProviderConfigService.normalizeCustomBaseUrl(
          'https://open.bigmodel.cn/api/paas/v4/',
          CustomProviderCompatibility.zhipuChatCompletions,
        ),
        'https://open.bigmodel.cn/api/paas/v4/',
      );
    });

    test('appends v1 for OpenAI-compatible endpoints', () {
      expect(
        ProviderConfigService.normalizeCustomBaseUrl(
          'https://api.example.com',
          CustomProviderCompatibility.openaiChatCompletions,
        ),
        'https://api.example.com/v1',
      );
    });
  });

  group('custom preset alias storage', () {
    test('saveCustomProviderPreset stores alias outside provider config',
        () async {
      rootfsFiles[configPath] = jsonEncode(<String, dynamic>{
        'agents': {
          'defaults': {
            'model': <String, dynamic>{},
          },
        },
        'models': {
          'providers': <String, dynamic>{},
        },
      });

      final preset = await ProviderConfigService.saveCustomProviderPreset(
        compatibility: CustomProviderCompatibility.openaiChatCompletions,
        apiKey: '',
        baseUrl: 'http://127.0.0.1:18080',
        modelId: 'qwen2-0.5b-local',
        providerId: 'local-llama-cpp',
        alias: '本地 Qwen',
      );

      final savedConfig =
          jsonDecode(rootfsFiles[configPath]!) as Map<String, dynamic>;
      final providerEntry = (savedConfig['models']
          as Map<String, dynamic>)['providers'] as Map<String, dynamic>;
      final localProvider =
          providerEntry['local-llama-cpp'] as Map<String, dynamic>;
      final savedMetadata =
          jsonDecode(rootfsFiles[metadataPath]!) as Map<String, dynamic>;
      final savedPresets = savedMetadata['presets'] as Map<String, dynamic>;

      expect(preset.alias, '本地 Qwen');
      expect(localProvider.containsKey('alias'), isFalse);
      expect(
        ((savedConfig['agents'] as Map<String, dynamic>)['defaults']
            as Map<String, dynamic>)['model'] as Map<String, dynamic>,
        containsPair('primary', 'local-llama-cpp/qwen2-0.5b-local'),
      );
      expect(
        (localProvider['baseUrl'] as String),
        'http://127.0.0.1:18080/v1',
      );
      expect(
        (savedPresets['local-llama-cpp'] as Map<String, dynamic>)['alias'],
        '本地 Qwen',
      );
    });

    test('migrateCustomProviderConfigIfNeeded removes legacy alias from config',
        () async {
      rootfsFiles[configPath] = jsonEncode(<String, dynamic>{
        'agents': {
          'defaults': {
            'model': {
              'primary': 'local-llama-cpp/qwen2-0.5b-local',
            },
            'models': {
              'local-llama-cpp/qwen2-0.5b-local': {
                'alias': '旧别名',
              },
            },
          },
        },
        'models': {
          'providers': {
            'local-llama-cpp': {
              'baseUrl': 'http://127.0.0.1:18080/v1',
              'api': 'openai-completions',
              'apiKey': '',
              'alias': '旧别名',
              'models': ['qwen2-0.5b-local'],
            },
          },
        },
      });

      await ProviderConfigService.migrateCustomProviderConfigIfNeeded();
      final config = await ProviderConfigService.readConfig();
      final savedConfig =
          jsonDecode(rootfsFiles[configPath]!) as Map<String, dynamic>;
      final providers = ((savedConfig['models']
          as Map<String, dynamic>)['providers'] as Map<String, dynamic>);
      final localProvider =
          providers['local-llama-cpp'] as Map<String, dynamic>;
      final savedMetadata =
          jsonDecode(rootfsFiles[metadataPath]!) as Map<String, dynamic>;
      final defaults = ((savedConfig['agents']
          as Map<String, dynamic>)['defaults'] as Map<String, dynamic>);
      final defaultModels = defaults['models'] as Map<String, dynamic>;
      final customPresets =
          config['customPresets'] as List<CustomProviderPreset>;

      expect(localProvider.containsKey('alias'), isFalse);
      expect(defaultModels.containsKey('local-llama-cpp/qwen2-0.5b-local'),
          isFalse);
      expect(
        ((savedMetadata['presets'] as Map<String, dynamic>)['local-llama-cpp']
            as Map<String, dynamic>)['alias'],
        '旧别名',
      );
      expect(customPresets, hasLength(1));
      expect(customPresets.single.alias, '旧别名');
    });
  });
}
