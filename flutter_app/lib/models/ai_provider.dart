import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

enum BaseUrlBehavior {
  useProviderDefaultWhenEmpty,
  preserveUserInput,
}

/// Metadata for an AI model provider that can be configured
/// to power the OpenClaw gateway.
class AiProvider {
  final String id;
  final String nameKey;
  final String descriptionKey;
  final IconData icon;
  final Color color;
  final String baseUrl;
  final List<String> defaultModels;
  final String apiKeyHint;
  final String? defaultApiKey;
  final bool supportsCustomBaseUrl;
  final String? endpointHelperKey;
  final String? modelHintKey;
  final BaseUrlBehavior baseUrlBehavior;
  final String? apiValue;
  final String? apiKeyUrl;
  final String? usageNoticeKey;
  final bool supportsModelCatalog;
  final bool modelCatalogRequiresApiKey;
  final bool supportsConnectionTest;

  const AiProvider({
    required this.id,
    required this.nameKey,
    required this.descriptionKey,
    required this.icon,
    required this.color,
    required this.baseUrl,
    required this.defaultModels,
    required this.apiKeyHint,
    this.defaultApiKey,
    this.supportsCustomBaseUrl = false,
    this.endpointHelperKey,
    this.modelHintKey,
    this.baseUrlBehavior = BaseUrlBehavior.useProviderDefaultWhenEmpty,
    this.apiValue,
    this.apiKeyUrl,
    this.usageNoticeKey,
    this.supportsModelCatalog = false,
    this.modelCatalogRequiresApiKey = false,
    this.supportsConnectionTest = false,
  });

  String name(AppLocalizations l10n) => l10n.t(nameKey);

  String description(AppLocalizations l10n) => l10n.t(descriptionKey);

  String endpointHelper(AppLocalizations l10n) =>
      l10n.t(endpointHelperKey ?? 'providerDetailEndpointHelper');

  String modelHint(AppLocalizations l10n) =>
      l10n.t(modelHintKey ?? 'providerDetailCustomModelHint');

  String? usageNotice(AppLocalizations l10n) =>
      usageNoticeKey == null ? null : l10n.t(usageNoticeKey!);

  bool matchesModel(String model) {
    return defaultModels.any((candidate) => model.contains(candidate)) ||
        model.contains(id);
  }

  String normalizeBaseUrl(String input) {
    final trimmed = input.trim();
    switch (baseUrlBehavior) {
      case BaseUrlBehavior.useProviderDefaultWhenEmpty:
        return trimmed.isEmpty ? baseUrl : trimmed;
      case BaseUrlBehavior.preserveUserInput:
        return trimmed;
    }
  }

  static const customOpenai = AiProvider(
    id: 'custom-openai',
    nameKey: 'providerNameCustomOpenai',
    descriptionKey: 'providerDescriptionCustomOpenai',
    icon: Icons.api,
    color: Color(0xFF0F766E),
    baseUrl: 'https://api.example.com/v1',
    defaultModels: [],
    apiKeyHint: 'sk-...',
    supportsCustomBaseUrl: true,
    endpointHelperKey: 'providerDetailEndpointHelperOpenaiCompatible',
    modelHintKey: 'providerDetailModelHintOpenaiCompatible',
    baseUrlBehavior: BaseUrlBehavior.preserveUserInput,
  );

  static const ywd = AiProvider(
    id: 'api7749',
    nameKey: 'providerNameYwd',
    descriptionKey: 'providerDescriptionYwd',
    icon: Icons.volunteer_activism,
    color: Color(0xFF7C3AED),
    baseUrl: 'https://api.774966.xyz/v1',
    defaultModels: [
      'ywd/deepseek-ai/deepseek-v4-flash',
    ],
    apiKeyHint: 'sk-...',
    defaultApiKey: 'sk-b2ZPC93WGxGGu74z01aCPmCX2TFOwsMPHCSgXZQCbYV6lGVl',
    supportsCustomBaseUrl: true,
    endpointHelperKey: 'providerDetailEndpointHelperOpenaiCompatible',
    modelHintKey: 'providerDetailModelHintOpenaiCompatible',
    apiValue: 'openai-completions',
    supportsModelCatalog: true,
    modelCatalogRequiresApiKey: true,
    supportsConnectionTest: true,
  );

  static const anthropic = AiProvider(
    id: 'anthropic',
    nameKey: 'providerNameAnthropic',
    descriptionKey: 'providerDescriptionAnthropic',
    icon: Icons.psychology,
    color: Color(0xFFD97706),
    baseUrl: 'https://api.anthropic.com/v1',
    defaultModels: [
      'claude-sonnet-4-20250514',
      'claude-opus-4-20250514',
      'claude-haiku-4-20250506',
      'claude-3-5-sonnet-20241022',
    ],
    apiKeyHint: 'sk-ant-...',
  );

  static const openai = AiProvider(
    id: 'openai',
    nameKey: 'providerNameOpenai',
    descriptionKey: 'providerDescriptionOpenai',
    icon: Icons.auto_awesome,
    color: Color(0xFF10A37F),
    baseUrl: 'https://api.openai.com/v1',
    defaultModels: [
      'gpt-4o',
      'gpt-4o-mini',
      'o1',
      'o1-mini',
      'gpt-4-turbo',
    ],
    apiKeyHint: 'sk-...',
    supportsCustomBaseUrl: true,
  );

  static const zhipu = AiProvider(
    id: 'zhipu',
    nameKey: 'providerNameZhipu',
    descriptionKey: 'providerDescriptionZhipu',
    icon: Icons.hub,
    color: Color(0xFF2563EB),
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    defaultModels: [
      'glm-5',
      'glm-4.7',
      'glm-4.6',
      'glm-4.5-air',
    ],
    apiKeyHint: 'your-api-key',
    supportsCustomBaseUrl: true,
    endpointHelperKey: 'providerDetailEndpointHelperZhipu',
    modelHintKey: 'providerDetailModelHintZhipu',
    apiValue: 'openai-completions',
  );

  static const google = AiProvider(
    id: 'google',
    nameKey: 'providerNameGoogle',
    descriptionKey: 'providerDescriptionGoogle',
    icon: Icons.diamond,
    color: Color(0xFF4285F4),
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    defaultModels: [
      'gemini-2.5-pro',
      'gemini-2.5-flash',
      'gemini-2.0-flash',
      'gemini-1.5-pro',
    ],
    apiKeyHint: 'AIza...',
  );

  static const nvidia = AiProvider(
    id: 'nvidia',
    nameKey: 'providerNameNvidia',
    descriptionKey: 'providerDescriptionNvidia',
    icon: Icons.memory,
    color: Color(0xFF76B900),
    baseUrl: 'https://integrate.api.nvidia.com/v1',
    defaultModels: [
      'deepseek-ai/deepseek-v4-pro',
      'deepseek-ai/deepseek-v4-flash',
      'moonshotai/kimi-k2.6',
      'openai/gpt-oss-120b',
      'z-ai/glm-5.2',
      'nvidia/nemotron-3-super-120b-a12b',
    ],
    apiKeyHint: 'nvapi-...',
    apiValue: 'openai-completions',
    apiKeyUrl: 'https://build.nvidia.com/settings/api-keys',
    usageNoticeKey: 'providerNoticeNvidiaFree',
    supportsModelCatalog: true,
    supportsConnectionTest: true,
  );

  static const deepseek = AiProvider(
    id: 'deepseek',
    nameKey: 'providerNameDeepseek',
    descriptionKey: 'providerDescriptionDeepseek',
    icon: Icons.explore,
    color: Color(0xFF0EA5E9),
    baseUrl: 'https://api.deepseek.com/v1',
    defaultModels: [
      'deepseek-v4-pro',
      'deepseek-v4-flash',
    ],
    apiKeyHint: 'sk-...',
    apiValue: 'openai-completions',
    apiKeyUrl: 'https://platform.deepseek.com/api_keys',
    supportsModelCatalog: true,
    modelCatalogRequiresApiKey: true,
    supportsConnectionTest: true,
  );

  static const qwen = AiProvider(
    id: 'qwen',
    nameKey: 'providerNameQwen',
    descriptionKey: 'providerDescriptionQwen',
    icon: Icons.cloud,
    color: Color(0xFF2563EB),
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    defaultModels: [
      'qwen-max',
      'qwen-plus',
      'qwen-turbo',
      'qwen3-coder-plus',
    ],
    apiKeyHint: 'sk-...',
    supportsCustomBaseUrl: true,
  );

  static const minimax = AiProvider(
    id: 'minimax',
    nameKey: 'providerNameMinimax',
    descriptionKey: 'providerDescriptionMinimax',
    icon: Icons.forum,
    color: Color(0xFFEC4899),
    baseUrl: 'https://api.minimax.chat/v1',
    defaultModels: [
      'MiniMax-Text-01',
      'MiniMax-M1',
      'abab7.5-chat',
    ],
    apiKeyHint: 'sk-...',
    supportsCustomBaseUrl: true,
  );

  static const doubao = AiProvider(
    id: 'doubao',
    nameKey: 'providerNameDoubao',
    descriptionKey: 'providerDescriptionDoubao',
    icon: Icons.token,
    color: Color(0xFFEA580C),
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    defaultModels: [
      'doubao-seed-2-0-pro-260215',
      'doubao-seed-2-0-lite-260215',
      'doubao-seed-2-0-mini-260215',
      'doubao-seed-1-8-251228',
    ],
    apiKeyHint: 'ark-...',
    supportsCustomBaseUrl: true,
  );

  /// All available AI providers.
  static const all = [
    customOpenai,
    ywd,
    deepseek,
    nvidia,
    zhipu,
    anthropic,
    openai,
    qwen,
    minimax,
    doubao,
    google,
  ];
}
