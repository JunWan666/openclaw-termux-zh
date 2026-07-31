import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/constants.dart';
import 'package:openclaw/models/ai_provider.dart';
import 'package:openclaw/models/custom_provider_preset.dart';
import 'package:openclaw/services/provider_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const configPath = '/root/.openclaw/openclaw.json';
  const metadataPath = '/root/.openclaw/app/custom-provider-presets.json';
  const channel = MethodChannel(AppConstants.channelName);

  late Map<String, String> rootfsFiles;
  late Map<String, int> writeCounts;

  setUp(() {
    rootfsFiles = <String, String>{};
    writeCounts = <String, int>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final arguments = Map<String, dynamic>.from(
        call.arguments as Map? ?? const <String, dynamic>{},
      );
      switch (call.method) {
        case 'readRootfsFile':
          return rootfsFiles[arguments['path'] as String];
        case 'writeRootfsFile':
          final path = arguments['path'] as String;
          rootfsFiles[path] = arguments['content'] as String;
          writeCounts.update(path, (count) => count + 1, ifAbsent: () => 1);
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

  group('minimal first-run configuration', () {
    test('creates a local token gateway without a model provider', () async {
      await ProviderConfigService.ensureInitialAppConfig();

      final config =
          jsonDecode(rootfsFiles[configPath]!) as Map<String, dynamic>;
      final gateway = config['gateway'] as Map<String, dynamic>;
      final auth = gateway['auth'] as Map<String, dynamic>;
      final agents = config['agents'] as Map<String, dynamic>;
      final defaults = agents['defaults'] as Map<String, dynamic>;

      expect(gateway['mode'], 'local');
      expect(gateway['port'], 18789);
      expect(gateway['bind'], 'loopback');
      expect(auth['mode'], 'token');
      expect(auth['token'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect((gateway['reload'] as Map<String, dynamic>)['mode'], 'hybrid');
      expect(defaults['workspace'], '/root/.openclaw/workspace');
      expect(config.containsKey('models'), isFalse);
    });

    test('preserves existing gateway and user configuration', () async {
      final original = <String, dynamic>{
        'gateway': {
          'mode': 'remote',
          'port': 19001,
          'bind': 'lan',
          'auth': {'mode': 'password', 'password': 'keep-me'},
        },
        'agents': {
          'defaults': {
            'workspace': '/root/custom-workspace',
            'model': {'primary': 'deepseek/deepseek-v4-flash'},
          },
        },
        'models': {
          'providers': {
            'deepseek': {'apiKey': 'keep-key'},
          },
        },
        'futureField': {'keep': true},
      };
      rootfsFiles[configPath] = jsonEncode(original);

      await ProviderConfigService.ensureInitialAppConfig();

      final config =
          jsonDecode(rootfsFiles[configPath]!) as Map<String, dynamic>;
      final gateway = config['gateway'] as Map<String, dynamic>;
      expect(gateway['mode'], 'remote');
      expect(gateway['port'], 19001);
      expect(gateway['bind'], 'lan');
      expect(
        gateway['auth'],
        {'mode': 'password', 'password': 'keep-me'},
      );
      expect((gateway['reload'] as Map<String, dynamic>)['mode'], 'hybrid');
      expect(config['agents'], original['agents']);
      expect(config['models'], original['models']);
      expect(config['futureField'], original['futureField']);
    });

    test('keeps the generated token stable on repeated initialization',
        () async {
      await ProviderConfigService.ensureInitialAppConfig();
      final first =
          jsonDecode(rootfsFiles[configPath]!) as Map<String, dynamic>;
      final firstToken = (((first['gateway'] as Map<String, dynamic>)['auth']
          as Map<String, dynamic>)['token'] as String);

      await ProviderConfigService.ensureInitialAppConfig();
      final second =
          jsonDecode(rootfsFiles[configPath]!) as Map<String, dynamic>;
      final secondToken = (((second['gateway'] as Map<String, dynamic>)['auth']
          as Map<String, dynamic>)['token'] as String);

      expect(secondToken, firstToken);
      expect(writeCounts[configPath], 1);
    });

    test('does not overwrite an invalid existing config', () async {
      const invalid = '{not-json';
      rootfsFiles[configPath] = invalid;

      await expectLater(
        ProviderConfigService.ensureInitialAppConfig(),
        throwsA(isA<FormatException>()),
      );
      expect(rootfsFiles[configPath], invalid);
      expect(writeCounts[configPath] ?? 0, 0);
    });
  });

  group('provider base URL policy', () {
    test('keeps built-in provider default paths', () {
      expect(
        AiProvider.openai.normalizeBaseUrl(AiProvider.openai.baseUrl),
        'https://api.openai.com/v1',
      );
      expect(
        AiProvider.nvidia.normalizeBaseUrl(AiProvider.nvidia.baseUrl),
        'https://integrate.api.nvidia.com/v1',
      );
      expect(
        AiProvider.zhipu.normalizeBaseUrl(AiProvider.zhipu.baseUrl),
        'https://open.bigmodel.cn/api/paas/v4',
      );
    });

    test('custom provider keeps user path and only trims whitespace', () {
      expect(
        AiProvider.customOpenai.normalizeBaseUrl(
          '  https://api.lkeap.cloud.tencent.com/plan/v3  ',
        ),
        'https://api.lkeap.cloud.tencent.com/plan/v3',
      );
    });
  });

  group('ProviderConfigService.normalizeCustomBaseUrl', () {
    test('keeps Zhipu base URL unchanged', () {
      expect(
        ProviderConfigService.normalizeCustomBaseUrl(
          'https://open.bigmodel.cn/api/paas/v4/',
          CustomProviderCompatibility.zhipuChatCompletions,
        ),
        'https://open.bigmodel.cn/api/paas/v4/',
      );
    });

    test('keeps OpenAI-compatible endpoint without appending v1', () {
      expect(
        ProviderConfigService.normalizeCustomBaseUrl(
          'https://api.example.com',
          CustomProviderCompatibility.openaiChatCompletions,
        ),
        'https://api.example.com',
      );
    });

    test('keeps an existing v1 path unchanged', () {
      expect(
        ProviderConfigService.normalizeCustomBaseUrl(
          'https://api.example.com/v1',
          CustomProviderCompatibility.openaiResponses,
        ),
        'https://api.example.com/v1',
      );
    });

    test('only trims whitespace around a custom path', () {
      expect(
        ProviderConfigService.normalizeCustomBaseUrl(
          '  https://example.com/custom/path/  ',
          CustomProviderCompatibility.openaiChatCompletions,
        ),
        'https://example.com/custom/path/',
      );
    });
  });

  group('custom preset alias storage', () {
    test('隐藏的旧内置提供商不会被识别为自定义预设', () async {
      rootfsFiles[configPath] = jsonEncode(<String, dynamic>{
        'models': {
          'providers': {
            'openrouter': {
              'baseUrl': 'https://openrouter.ai/api/v1',
              'apiKey': 'legacy-key',
              'models': ['openai/gpt-4o'],
            },
            'xai': {
              'baseUrl': 'https://api.x.ai/v1',
              'apiKey': 'legacy-key',
              'models': ['grok-3'],
            },
          },
        },
      });

      final config = await ProviderConfigService.readConfig();

      expect(config['customPresets'], isEmpty);
    });

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
        'http://127.0.0.1:18080',
      );
      expect(preset.baseUrl, 'http://127.0.0.1:18080');
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

    test('migration does not rewrite a saved custom base URL', () async {
      final originalConfig = jsonEncode(<String, dynamic>{
        'agents': {
          'defaults': {
            'model': {
              'primary': 'custom-proxy/demo-model',
            },
          },
        },
        'models': {
          'providers': {
            'custom-proxy': {
              'baseUrl': 'https://api.lkeap.cloud.tencent.com/plan/v3',
              'api': 'openai-completions',
              'apiKey': 'test-key',
              'models': ['demo-model'],
            },
          },
        },
      });
      rootfsFiles[configPath] = originalConfig;
      rootfsFiles[metadataPath] = jsonEncode({'presets': {}});

      await ProviderConfigService.migrateCustomProviderConfigIfNeeded();

      expect(rootfsFiles[configPath], originalConfig);
      expect(writeCounts[configPath] ?? 0, 0);
      expect(writeCounts[metadataPath] ?? 0, 0);
    });
  });
}
