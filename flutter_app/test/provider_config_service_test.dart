import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/models/custom_provider_preset.dart';
import 'package:openclaw/services/provider_config_service.dart';

void main() {
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
}
