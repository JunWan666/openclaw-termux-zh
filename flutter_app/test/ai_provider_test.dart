import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/l10n/app_localizations.dart';
import 'package:openclaw/models/ai_provider.dart';

void main() {
  test('提供商目录按产品顺序展示且不再包含 OpenRouter 和 xAI', () {
    expect(
      AiProvider.all.map((provider) => provider.id).take(5),
      const ['custom-openai', 'deepseek', 'open7749', 'nvidia', 'zhipu'],
    );
    expect(
      AiProvider.all.map((provider) => provider.id),
      isNot(contains(anyOf('openrouter', 'xai'))),
    );
  });

  test('DeepSeek 和 NVIDIA 使用当前模型、官方 Key 页面与在线工具', () {
    expect(
      AiProvider.deepseek.defaultModels,
      const ['deepseek-v4-pro', 'deepseek-v4-flash'],
    );
    expect(
      AiProvider.deepseek.apiKeyUrl,
      'https://platform.deepseek.com/api_keys',
    );
    expect(AiProvider.deepseek.supportsModelCatalog, isTrue);
    expect(AiProvider.deepseek.modelCatalogRequiresApiKey, isTrue);
    expect(AiProvider.deepseek.supportsConnectionTest, isTrue);

    expect(
      AiProvider.nvidia.defaultModels,
      containsAll(const [
        'deepseek-ai/deepseek-v4-pro',
        'deepseek-ai/deepseek-v4-flash',
        'openai/gpt-oss-120b',
      ]),
    );
    expect(
      AiProvider.nvidia.apiKeyUrl,
      'https://build.nvidia.com/settings/api-keys',
    );
    expect(AiProvider.nvidia.supportsModelCatalog, isTrue);
    expect(AiProvider.nvidia.supportsConnectionTest, isTrue);
  });

  test('7749API 公益提供商预置端点、模型并支持在线模型列表', () {
    expect(AiProvider.ywd.nameKey, 'providerNameYwd');
    expect(AiProvider.ywd.id, 'open7749');
    expect(AiProvider.ywd.baseUrl, 'https://open.774966.xyz/v1');
    expect(
      AiProvider.ywd.defaultModels,
      const ['ywd/openai/gpt-oss-120b'],
    );
    expect(AiProvider.ywd.defaultApiKey, isNull);
    expect(AiProvider.ywd.apiKeyUrl, 'https://open.774966.xyz/');
    expect(AiProvider.ywd.supportsModelCatalog, isTrue);
    expect(AiProvider.ywd.modelCatalogRequiresApiKey, isTrue);
    expect(AiProvider.ywd.supportsConnectionTest, isTrue);
  });

  test('中文名称符合产品命名', () {
    final l10n = AppLocalizations(const Locale('zh'));

    expect(AiProvider.customOpenai.name(l10n), '自定义 OpenAI 兼容模型');
    expect(AiProvider.nvidia.name(l10n), '英伟达（NVIDIA 免费）');
  });
}
