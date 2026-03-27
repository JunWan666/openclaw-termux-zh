enum CustomProviderCompatibility {
  autoDetect(apiValue: null, labelKey: 'customProviderCompatibilityAuto'),
  openaiChatCompletions(
    apiValue: 'openai-completions',
    labelKey: 'customProviderCompatibilityOpenai',
  ),
  zhipuChatCompletions(
    apiValue: 'openai-completions',
    labelKey: 'customProviderCompatibilityZhipu',
  ),
  openaiResponses(
    apiValue: 'openai-responses',
    labelKey: 'customProviderCompatibilityOpenaiResponses',
  ),
  anthropicMessages(
    apiValue: 'anthropic-messages',
    labelKey: 'customProviderCompatibilityAnthropic',
  ),
  googleGenerativeAi(
    apiValue: 'google-generative-ai',
    labelKey: 'customProviderCompatibilityGoogle',
  );

  const CustomProviderCompatibility({
    required this.apiValue,
    required this.labelKey,
  });

  final String? apiValue;
  final String labelKey;

  bool get appendsV1 =>
      this == CustomProviderCompatibility.openaiChatCompletions ||
      this == CustomProviderCompatibility.openaiResponses;

  static bool _looksLikeZhipuBaseUrl(String? baseUrl) {
    final host = Uri.tryParse(baseUrl?.trim() ?? '')?.host.toLowerCase() ?? '';
    return host.contains('bigmodel.cn');
  }

  static CustomProviderCompatibility fromApiValue(String? apiValue) {
    for (final compatibility in values) {
      if (compatibility == CustomProviderCompatibility.zhipuChatCompletions) {
        continue;
      }
      if (compatibility.apiValue == apiValue) {
        return compatibility;
      }
    }
    return CustomProviderCompatibility.autoDetect;
  }

  static CustomProviderCompatibility resolveSavedCompatibility({
    required String? apiValue,
    required String? baseUrl,
  }) {
    if (apiValue ==
            CustomProviderCompatibility.openaiChatCompletions.apiValue &&
        _looksLikeZhipuBaseUrl(baseUrl)) {
      return CustomProviderCompatibility.zhipuChatCompletions;
    }
    return fromApiValue(apiValue);
  }
}

class CustomProviderPreset {
  const CustomProviderPreset({
    required this.providerId,
    required this.modelId,
    required this.baseUrl,
    required this.apiKey,
    required this.alias,
    required this.compatibility,
  });

  final String providerId;
  final String modelId;
  final String baseUrl;
  final String apiKey;
  final String alias;
  final CustomProviderCompatibility compatibility;

  String get modelRef => '$providerId/$modelId';

  String get displayName => alias.isNotEmpty ? alias : modelId;
}
