import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/custom_provider_preset.dart';
import 'native_bridge.dart';
import 'preferences_service.dart';
import 'provider_config_service.dart';

class LocalModelRuntimeRelease {
  const LocalModelRuntimeRelease({
    required this.tagName,
    required this.assetName,
    required this.downloadUrl,
  });

  final String tagName;
  final String assetName;
  final String downloadUrl;
}

class LocalModelModuleInfo {
  const LocalModelModuleInfo({
    required this.version,
    required this.assetName,
    required this.downloadUrl,
    required this.installedAt,
  });

  final String version;
  final String assetName;
  final String downloadUrl;
  final String installedAt;

  Map<String, dynamic> toJson() => {
        'version': version,
        'assetName': assetName,
        'downloadUrl': downloadUrl,
        'installedAt': installedAt,
      };

  factory LocalModelModuleInfo.fromJson(Map<String, dynamic> json) {
    return LocalModelModuleInfo(
      version: json['version']?.toString().trim() ?? '',
      assetName: json['assetName']?.toString().trim() ?? '',
      downloadUrl: json['downloadUrl']?.toString().trim() ?? '',
      installedAt: json['installedAt']?.toString().trim() ?? '',
    );
  }
}

class LocalModelDownloadedModel {
  const LocalModelDownloadedModel({
    required this.fileName,
    required this.path,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String fileName;
  final String path;
  final int sizeBytes;
  final DateTime modifiedAt;

  String get defaultAlias {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.gguf')
        ? fileName.substring(0, fileName.length - 5)
        : fileName;
  }
}

class LocalModelDownloadException implements Exception {
  const LocalModelDownloadException(
    this.message, {
    required this.code,
    this.statusCode,
    this.url,
    this.details,
  });

  final String message;
  final String code;
  final int? statusCode;
  final String? url;
  final String? details;

  @override
  String toString() => message;
}

class LocalModelDownloadProgress {
  const LocalModelDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
    required this.sourceHost,
    required this.attempt,
    required this.usingFallbackSource,
    this.bytesPerSecond,
    this.eta,
  });

  final int receivedBytes;
  final int totalBytes;
  final String sourceHost;
  final int attempt;
  final bool usingFallbackSource;
  final double? bytesPerSecond;
  final Duration? eta;

  double? get fraction {
    if (totalBytes <= 0) {
      return null;
    }
    return (receivedBytes / totalBytes).clamp(0, 1);
  }
}

enum LocalModelPerformanceMode {
  memorySaver,
  balanced,
  performance,
}

class LocalModelRuntimePreferences {
  const LocalModelRuntimePreferences({
    required this.maxCpuCores,
    required this.memoryLimitMiB,
    required this.performanceMode,
  });

  const LocalModelRuntimePreferences.defaults()
      : maxCpuCores = 0,
        memoryLimitMiB = 0,
        performanceMode = LocalModelPerformanceMode.balanced;

  final int maxCpuCores;
  final int memoryLimitMiB;
  final LocalModelPerformanceMode performanceMode;

  bool get usesAutoCpuCores => maxCpuCores <= 0;
  bool get usesAutoMemoryLimit => memoryLimitMiB <= 0;
}

class LocalModelHardwareProfile {
  const LocalModelHardwareProfile({
    required this.cpuCount,
    required this.memoryKiB,
    required this.freeStorageKiB,
  });

  const LocalModelHardwareProfile.empty()
      : cpuCount = 0,
        memoryKiB = 0,
        freeStorageKiB = 0;

  final int cpuCount;
  final int memoryKiB;
  final int freeStorageKiB;

  double get memoryGiB => memoryKiB / 1024 / 1024;

  double get freeStorageGiB => freeStorageKiB / 1024 / 1024;
}

class LocalModelRecommendation {
  const LocalModelRecommendation({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;
}

class LocalModelCatalogEntry {
  const LocalModelCatalogEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.bestFor,
    required this.fileName,
    required this.downloadUrl,
    required this.defaultAlias,
    required this.sizeLabel,
    required this.sourceLabel,
    required this.group,
    required this.minimumMemoryGiB,
    required this.recommendedMemoryGiB,
    this.keywords = const <String>[],
  });

  final String id;
  final String title;
  final String subtitle;
  final String bestFor;
  final String fileName;
  final String downloadUrl;
  final String defaultAlias;
  final String sizeLabel;
  final String sourceLabel;
  final String group;
  final double minimumMemoryGiB;
  final double recommendedMemoryGiB;
  final List<String> keywords;

  bool matchesQuery(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }

    final haystacks = <String>[
      id,
      title,
      subtitle,
      bestFor,
      fileName,
      defaultAlias,
      group,
      sourceLabel,
      ...keywords,
    ];

    for (final haystack in haystacks) {
      if (haystack.toLowerCase().contains(normalized)) {
        return true;
      }
    }
    return false;
  }
}

class LocalModelDownloadSelection {
  const LocalModelDownloadSelection({
    required this.title,
    required this.fileName,
    required this.downloadUrl,
    required this.defaultAlias,
    required this.sourceLabel,
    this.subtitle = '',
  });

  final String title;
  final String subtitle;
  final String fileName;
  final String downloadUrl;
  final String defaultAlias;
  final String sourceLabel;
}

class LocalModelServerConfig {
  const LocalModelServerConfig({
    required this.modelPath,
    required this.alias,
    required this.port,
    required this.contextSize,
    required this.threads,
    required this.threadsBatch,
    required this.batchSize,
    required this.ubatchSize,
  });

  final String modelPath;
  final String alias;
  final int port;
  final int contextSize;
  final int threads;
  final int threadsBatch;
  final int batchSize;
  final int ubatchSize;

  Map<String, dynamic> toJson() => {
        'modelPath': modelPath,
        'alias': alias,
        'port': port,
        'contextSize': contextSize,
        'threads': threads,
        'threadsBatch': threadsBatch,
        'batchSize': batchSize,
        'ubatchSize': ubatchSize,
      };

  factory LocalModelServerConfig.fromJson(Map<String, dynamic> json) {
    return LocalModelServerConfig(
      modelPath: json['modelPath']?.toString().trim() ?? '',
      alias: json['alias']?.toString().trim() ?? '',
      port: (json['port'] as num?)?.toInt() ?? LocalModelService.defaultPort,
      contextSize: (json['contextSize'] as num?)?.toInt() ??
          LocalModelService.defaultContextSize,
      threads: (json['threads'] as num?)?.toInt() ?? 0,
      threadsBatch: (json['threadsBatch'] as num?)?.toInt() ?? 0,
      batchSize: (json['batchSize'] as num?)?.toInt() ?? 0,
      ubatchSize: (json['ubatchSize'] as num?)?.toInt() ?? 0,
    );
  }
}

class LocalModelServerTuning {
  const LocalModelServerTuning({
    required this.threads,
    required this.threadsBatch,
    required this.batchSize,
    required this.ubatchSize,
  });

  final int threads;
  final int threadsBatch;
  final int batchSize;
  final int ubatchSize;
}

class LocalModelRuntimeSample {
  const LocalModelRuntimeSample({
    required this.pid,
    required this.rssKiB,
    required this.threadCount,
    required this.processTicks,
    required this.cpuTotalTicks,
    required this.sampledAt,
  });

  final int pid;
  final int rssKiB;
  final int threadCount;
  final int processTicks;
  final int cpuTotalTicks;
  final DateTime sampledAt;
}

class LocalModelRuntimeUsage {
  const LocalModelRuntimeUsage({
    required this.pid,
    required this.rssKiB,
    required this.threadCount,
    required this.cpuPercent,
    required this.approxCoreCount,
    required this.sampledAt,
  });

  final int pid;
  final int rssKiB;
  final int threadCount;
  final double? cpuPercent;
  final double? approxCoreCount;
  final DateTime sampledAt;

  double get rssMiB => rssKiB / 1024;
}

class LocalModelState {
  const LocalModelState({
    required this.architecture,
    required this.archSupported,
    required this.installed,
    required this.running,
    required this.endpointReachable,
    required this.hardware,
    required this.runtimePreferences,
    required this.recommendations,
    required this.models,
    required this.recentLogs,
    this.installedVersion,
    this.activeConfig,
  });

  const LocalModelState.empty()
      : architecture = '',
        archSupported = false,
        installed = false,
        running = false,
        endpointReachable = false,
        installedVersion = null,
        activeConfig = null,
        hardware = const LocalModelHardwareProfile.empty(),
        runtimePreferences = const LocalModelRuntimePreferences.defaults(),
        recommendations = const <LocalModelRecommendation>[],
        models = const <LocalModelDownloadedModel>[],
        recentLogs = const <String>[];

  final String architecture;
  final bool archSupported;
  final bool installed;
  final bool running;
  final bool endpointReachable;
  final String? installedVersion;
  final LocalModelServerConfig? activeConfig;
  final LocalModelHardwareProfile hardware;
  final LocalModelRuntimePreferences runtimePreferences;
  final List<LocalModelRecommendation> recommendations;
  final List<LocalModelDownloadedModel> models;
  final List<String> recentLogs;

  String get endpointUrl =>
      'http://127.0.0.1:${activeConfig?.port ?? LocalModelService.defaultPort}/v1';
}

class LocalModelService {
  static const defaultPort = 18080;
  static const defaultContextSize = 4096;
  static const localProviderId = 'local-llama-cpp';
  static const modelCatalog = <LocalModelCatalogEntry>[
    LocalModelCatalogEntry(
      id: 'qwen2-0.5b-q4km',
      title: 'Qwen2 0.5B · 超轻量',
      subtitle: '先试通本地模型最合适，下载快、占用小、回复也最快。',
      bestFor: '4GB 左右内存手机，或者你只是想先验证本地模型能不能跑起来。',
      fileName: 'qwen2-0_5b-instruct-q4_k_m.gguf',
      downloadUrl:
          'https://huggingface.co/Qwen/Qwen2-0.5B-Instruct-GGUF/resolve/main/qwen2-0_5b-instruct-q4_k_m.gguf?download=true',
      defaultAlias: 'qwen2-0.5b-local',
      sizeLabel: '约 353 MB',
      sourceLabel: 'Qwen 官方 GGUF',
      group: 'starter',
      minimumMemoryGiB: 3.5,
      recommendedMemoryGiB: 4.0,
      keywords: ['入门', '超轻量', '测试', '聊天', 'qwen'],
    ),
    LocalModelCatalogEntry(
      id: 'qwen2.5-1.5b-q4km',
      title: 'Qwen2.5 1.5B · 入门聊天',
      subtitle: '比 0.5B 稳很多，适合日常问答、翻译和简单助手。',
      bestFor: '4GB 到 6GB 内存手机，想要速度和效果比较平衡。',
      fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
      downloadUrl:
          'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf?download=true',
      defaultAlias: 'qwen2.5-1.5b-local',
      sizeLabel: '约 1.12 GB',
      sourceLabel: 'Qwen 官方 GGUF',
      group: 'starter',
      minimumMemoryGiB: 4.5,
      recommendedMemoryGiB: 6.0,
      keywords: ['入门', '聊天', '翻译', '轻量', 'qwen2.5'],
    ),
    LocalModelCatalogEntry(
      id: 'qwen2.5-3b-q4km',
      title: 'Qwen2.5 3B · 日常主力',
      subtitle: '大多数人最值得先试的一档，聊天、总结、改写都比较均衡。',
      bestFor: '6GB 到 8GB 内存手机，想要拿来长期日常使用。',
      fileName: 'qwen2.5-3b-instruct-q4_k_m.gguf',
      downloadUrl:
          'https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf?download=true',
      defaultAlias: 'qwen2.5-3b-local',
      sizeLabel: '约 2.0 GB',
      sourceLabel: 'Qwen 官方 GGUF',
      group: 'daily',
      minimumMemoryGiB: 6.0,
      recommendedMemoryGiB: 8.0,
      keywords: ['日常', '聊天', '总结', '主力', 'qwen2.5'],
    ),
    LocalModelCatalogEntry(
      id: 'qwen2.5-coder-3b-q4km',
      title: 'Qwen2.5 Coder 3B · 写代码',
      subtitle: '偏代码用途，写脚本、看报错、改配置通常会更顺手。',
      bestFor: '6GB 到 8GB 内存手机，而且你主要是拿它写代码。',
      fileName: 'qwen2.5-coder-3b-instruct-q4_k_m.gguf',
      downloadUrl:
          'https://huggingface.co/Qwen/Qwen2.5-Coder-3B-Instruct-GGUF/resolve/main/qwen2.5-coder-3b-instruct-q4_k_m.gguf?download=true',
      defaultAlias: 'qwen2.5-coder-3b-local',
      sizeLabel: '约 2.0 GB',
      sourceLabel: 'Qwen 官方 GGUF',
      group: 'coding',
      minimumMemoryGiB: 6.0,
      recommendedMemoryGiB: 8.0,
      keywords: ['代码', '编程', '脚本', 'coder', 'qwen2.5'],
    ),
    LocalModelCatalogEntry(
      id: 'qwen3-4b-q4km',
      title: 'Qwen3 4B · 更强一点',
      subtitle: '回答质量会比 3B 更稳，但更吃内存，也更容易发热。',
      bestFor: '8GB 到 12GB 内存手机，愿意用更高资源换更好效果。',
      fileName: 'Qwen3-4B-Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf?download=true',
      defaultAlias: 'qwen3-4b-local',
      sizeLabel: '约 2.5 GB',
      sourceLabel: 'Qwen 官方 GGUF',
      group: 'strong',
      minimumMemoryGiB: 8.0,
      recommendedMemoryGiB: 10.0,
      keywords: ['更强', '聊天', '推理', 'qwen3'],
    ),
    LocalModelCatalogEntry(
      id: 'qwen3-8b-q4km',
      title: 'Qwen3 8B · 大模型尝试',
      subtitle: '效果更好，但对手机压力也明显更大，不适合小内存设备直接上。',
      bestFor: '12GB 以上内存手机，并且能接受更慢、更热和更耗电。',
      fileName: 'Qwen3-8B-Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf?download=true',
      defaultAlias: 'qwen3-8b-local',
      sizeLabel: '约 5.03 GB',
      sourceLabel: 'Qwen 官方 GGUF',
      group: 'strong',
      minimumMemoryGiB: 12.0,
      recommendedMemoryGiB: 14.0,
      keywords: ['8b', '大模型', '更强', '推理', 'qwen3'],
    ),
    LocalModelCatalogEntry(
      id: 'gemma4-e2b-q4',
      title: 'Gemma 4 E2B · 新热点轻量版',
      subtitle: 'Gemma 4 现在确实很火，这个是更适合手机先试的轻量版本。',
      bestFor: '6GB 到 8GB 内存手机，想试 Gemma 4，但又不想一上来就下太大的模型。',
      fileName: 'gemma-4-e2b-it-q4_0-imat.gguf',
      downloadUrl:
          'https://huggingface.co/Shariyat/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_0-imat.gguf?download=true',
      defaultAlias: 'gemma4-e2b-local',
      sizeLabel: '约 3.36 GB',
      sourceLabel: 'Gemma 4 GGUF',
      group: 'strong',
      minimumMemoryGiB: 6.0,
      recommendedMemoryGiB: 8.0,
      keywords: ['gemma4', 'gemma 4', '热门', '新模型', '谷歌'],
    ),
    LocalModelCatalogEntry(
      id: 'gemma4-e4b-q4km',
      title: 'Gemma 4 E4B · 热门主力版',
      subtitle: '效果会更强，但对手机压力也更大，适合大内存设备测试。',
      bestFor: '10GB 以上内存手机，想认真试试 Gemma 4 的主力版本。',
      fileName: 'google_gemma-4-E4B-it-Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/bartowski/google_gemma-4-E4B-it-GGUF/resolve/main/google_gemma-4-E4B-it-Q4_K_M.gguf?download=true',
      defaultAlias: 'gemma4-e4b-local',
      sizeLabel: '约 5.34 GB',
      sourceLabel: 'Gemma 4 GGUF',
      group: 'strong',
      minimumMemoryGiB: 10.0,
      recommendedMemoryGiB: 12.0,
      keywords: ['gemma4', 'gemma 4', '热门', '主力', '谷歌'],
    ),
  ];

  static const _githubApiLatestRelease =
      'https://api.github.com/repos/ggml-org/llama.cpp/releases/latest';
  static const _fallbackReleaseTag = 'b8763';

  static const _moduleRootfsDir = 'root/.openclaw/modules/llama.cpp';
  static const _modelsRootfsDir = 'root/.openclaw/models';
  static const _moduleInfoRootfsPath = '$_moduleRootfsDir/module.json';
  static const _serverConfigRootfsPath = '$_moduleRootfsDir/server.json';
  static const _serverLogRootfsPath = '$_moduleRootfsDir/logs/server.log';
  static const _installLogRootfsPath = '$_moduleRootfsDir/logs/install.log';
  static const _downloadLogRootfsPath = '$_moduleRootfsDir/logs/download.log';
  static const _binaryGuestPath = '/usr/local/bin/llama-server';
  static const _runtimeGuestDir = '/root/.openclaw/modules/llama.cpp/runtime';
  static const _runtimeCurrentGuestDir = '$_runtimeGuestDir/current';
  static const _runtimePidGuestPath = '$_runtimeGuestDir/server.pid';
  static const _modelsGuestDir = '/root/.openclaw/models';
  static const _serverLogGuestPath =
      '/root/.openclaw/modules/llama.cpp/logs/server.log';
  static const _installLogGuestPath =
      '/root/.openclaw/modules/llama.cpp/logs/install.log';

  static Future<LocalModelState> readState() async {
    final architecture = await NativeBridge.getArch();
    final installed = await _isInstalled();
    final running = await _isServiceRunning();
    final activeConfig = await _readServerConfig();
    final port = activeConfig?.port ?? defaultPort;
    final endpointReachable =
        installed ? await _isEndpointReachable(port) : false;
    final hardware = await _readHardwareProfile();
    final runtimePreferences = await readRuntimePreferences();
    final models = await _listModels();
    final recentLogs = installed ? await _readRecentLogs() : const <String>[];
    final moduleInfo = await _readModuleInfo();

    return LocalModelState(
      architecture: architecture,
      archSupported: _assetNamePatternForArch(architecture) != null,
      installed: installed,
      running: running || endpointReachable,
      endpointReachable: endpointReachable,
      installedVersion:
          moduleInfo?.version.isNotEmpty == true ? moduleInfo!.version : null,
      activeConfig: activeConfig,
      hardware: hardware,
      runtimePreferences: runtimePreferences,
      recommendations: buildRecommendations(hardware),
      models: models,
      recentLogs: recentLogs,
    );
  }

  static Future<void> installOrUpdateLatest({
    void Function(List<String> lines)? onLogChanged,
  }) async {
    await _ensureRuntimeReady();
    final release = await _resolveLatestReleaseForCurrentArch();

    if (await _isServiceRunning()) {
      await stop();
    }

    await _runCommandWithLogs(
      _buildInstallCommand(release),
      logRootfsPath: _installLogRootfsPath,
      onLogChanged: onLogChanged,
      timeoutSeconds: 1800,
    );

    final moduleInfo = LocalModelModuleInfo(
      version: release.tagName,
      assetName: release.assetName,
      downloadUrl: release.downloadUrl,
      installedAt: DateTime.now().toUtc().toIso8601String(),
    );
    await NativeBridge.writeRootfsFile(
      _moduleInfoRootfsPath,
      const JsonEncoder.withIndent('  ').convert(moduleInfo.toJson()),
    );
  }

  static Future<void> uninstallRuntime() async {
    final activeConfig = await _readServerConfig();
    final port = activeConfig?.port ?? defaultPort;
    if (await _isServiceRunning()) {
      await stop();
    }

    await NativeBridge.runInProot(
      '''
rm -f ${_shellQuote(_binaryGuestPath)}
rm -rf ${_shellQuote('/root/.openclaw/modules/llama.cpp')}
''',
      timeout: 120,
    );
    await _waitForStopped(port);
  }

  static Future<void> downloadModel({
    required String url,
    required String fileName,
    void Function(List<String> lines)? onLogChanged,
    void Function(LocalModelDownloadProgress progress)? onProgressChanged,
  }) async {
    await _ensureRuntimeReady();
    final resolvedUrl = url.trim();
    final resolvedFileName = sanitizeModelFileName(fileName);
    if (resolvedUrl.isEmpty) {
      throw Exception(_localized(
        '模型下载链接不能为空。',
        'Model download URL cannot be empty.',
      ));
    }
    if (resolvedFileName.isEmpty) {
      throw Exception(_localized(
        '模型文件名不能为空。',
        'Model file name cannot be empty.',
      ));
    }

    final parsedUrl = Uri.tryParse(resolvedUrl);
    if (parsedUrl == null ||
        !parsedUrl.hasScheme ||
        parsedUrl.host.trim().isEmpty) {
      throw Exception(_localized(
        '模型下载链接不合法，请检查后再试。',
        'Model download URL is invalid. Please check it and try again.',
      ));
    }

    final filesDir = await NativeBridge.getFilesDir();
    final modelsDir = Directory('$filesDir/rootfs/ubuntu/$_modelsRootfsDir');
    final targetFile = File('${modelsDir.path}/$resolvedFileName');
    final tempFile = File('${targetFile.path}.part');
    final logFile = File('$filesDir/rootfs/ubuntu/$_downloadLogRootfsPath');

    await modelsDir.create(recursive: true);
    await logFile.parent.create(recursive: true);

    final logLines = <String>[];

    void emitLiveLogs() {
      if (onLogChanged != null) {
        onLogChanged(List<String>.unmodifiable(logLines));
      }
    }

    Future<void> flushLogs() async {
      final content = logLines.isEmpty ? '' : '${logLines.join('\n')}\n';
      await logFile.writeAsString(content, flush: true);
      emitLiveLogs();
    }

    Future<void> addLog(String message) async {
      logLines.add('[${DateTime.now().toIso8601String()}] $message');
      await flushLogs();
    }

    await logFile.writeAsString('', flush: true);
    emitLiveLogs();

    final candidateUrls = _buildDownloadCandidateUris(parsedUrl);
    await addLog('Preparing model download for $resolvedFileName');
    if (candidateUrls.length > 1) {
      await addLog(
          'Primary source may be rate-limited; a fallback source is ready.');
    }

    LocalModelDownloadException? lastError;

    for (var sourceIndex = 0;
        sourceIndex < candidateUrls.length;
        sourceIndex++) {
      final candidateUrl = candidateUrls[sourceIndex];
      final candidateHost = candidateUrl.host;
      final usingFallbackSource = sourceIndex > 0;

      for (var attempt = 1; attempt <= 3; attempt++) {
        var lastLoggedStep = -1;
        final progressTracker = _TransferProgressTracker();

        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }

          await addLog(
            usingFallbackSource
                ? 'Trying fallback source $candidateHost (attempt $attempt/3)'
                : 'Downloading from $candidateHost (attempt $attempt/3)',
          );
          onProgressChanged?.call(
            LocalModelDownloadProgress(
              receivedBytes: 0,
              totalBytes: 0,
              sourceHost: candidateHost,
              attempt: attempt,
              usingFallbackSource: usingFallbackSource,
              bytesPerSecond: null,
              eta: null,
            ),
          );

          await _downloadModelFile(
            url: candidateUrl,
            destinationPath: tempFile.path,
            onReceiveProgress: (received, total) {
              final progressEstimate = progressTracker.describe(
                received,
                total,
              );
              onProgressChanged?.call(
                LocalModelDownloadProgress(
                  receivedBytes: received,
                  totalBytes: total,
                  sourceHost: candidateHost,
                  attempt: attempt,
                  usingFallbackSource: usingFallbackSource,
                  bytesPerSecond: progressEstimate.bytesPerSecond,
                  eta: progressEstimate.eta,
                ),
              );

              const logStepBytes = 5 * 1024 * 1024;
              final currentStep = received ~/ logStepBytes;
              if (currentStep <= lastLoggedStep) {
                return;
              }
              lastLoggedStep = currentStep;

              final totalLabel = total > 0
                  ? ' / ${_formatByteCount(total)} (${((received / total) * 100).clamp(0, 100).toStringAsFixed(1)}%)'
                  : '';
              logLines.add(
                '[${DateTime.now().toIso8601String()}] Downloaded ${_formatByteCount(received)}$totalLabel',
              );
              emitLiveLogs();
            },
          );

          if (await targetFile.exists()) {
            await targetFile.delete();
          }
          await tempFile.rename(targetFile.path);
          final sizeBytes = await targetFile.length();
          onProgressChanged?.call(
            LocalModelDownloadProgress(
              receivedBytes: sizeBytes,
              totalBytes: sizeBytes,
              sourceHost: candidateHost,
              attempt: attempt,
              usingFallbackSource: usingFallbackSource,
              bytesPerSecond: null,
              eta: Duration.zero,
            ),
          );

          await addLog('Model saved to ${targetFile.path}');
          await addLog('Download complete (${_formatByteCount(sizeBytes)}).');
          return;
        } on DioException catch (error) {
          lastError = _mapDownloadFailure(
            error,
            attemptedUrl: candidateUrl,
            fallbackSource: usingFallbackSource,
          );
          await addLog(lastError.message);

          if (attempt < 3 && _shouldRetryDownload(error)) {
            final delay = _retryDelayFor(error, attempt);
            await addLog('Retrying in ${delay.inSeconds}s...');
            await Future.delayed(delay);
            continue;
          }
          break;
        } on LocalModelDownloadException catch (error) {
          lastError = error;
          await addLog(lastError.message);
          break;
        } catch (error) {
          lastError = LocalModelDownloadException(
            _localized(
              '下载时发生异常：$error',
              'Unexpected download error: $error',
            ),
            code: 'unknown',
            url: candidateUrl.toString(),
            details: error.toString(),
          );
          await addLog(lastError.message);
          break;
        } finally {
          await flushLogs();
          if (await tempFile.exists()) {
            try {
              await tempFile.delete();
            } catch (_) {}
          }
        }
      }
    }

    await flushLogs();
    throw _finalizeDownloadFailure(
      lastError ??
          LocalModelDownloadException(
            _localized(
              '模型下载失败，请稍后再试。',
              'Model download failed. Please try again later.',
            ),
            code: 'unknown',
            url: resolvedUrl,
          ),
      triedFallbackSource: candidateUrls.length > 1,
    );
  }

  static Future<void> deleteModel(LocalModelDownloadedModel model) async {
    final activeConfig = await _readServerConfig();
    if (activeConfig?.modelPath == '$_modelsGuestDir/${model.fileName}' &&
        await _isServiceRunning()) {
      await stop();
    }

    await NativeBridge.runInProot(
      'rm -f ${_shellQuote('$_modelsGuestDir/${model.fileName}')}',
      timeout: 60,
    );
  }

  static Future<void> start({
    required LocalModelDownloadedModel model,
    required String alias,
    int port = defaultPort,
    int contextSize = defaultContextSize,
    int? threads,
    int? threadsBatch,
    int? batchSize,
    int? ubatchSize,
  }) async {
    if (!await _isInstalled()) {
      throw Exception('llama.cpp runtime is not installed.');
    }

    final resolvedAlias =
        alias.trim().isEmpty ? model.defaultAlias : alias.trim();
    final resolvedPort = port <= 0 ? defaultPort : port;
    final resolvedContext = contextSize <= 0 ? defaultContextSize : contextSize;
    final hardware = await _readHardwareProfile();
    final runtimePreferences = await readRuntimePreferences();
    final tuning = recommendServerTuning(
      hardware: hardware,
      modelSizeBytes: model.sizeBytes,
      contextSize: resolvedContext,
      runtimePreferences: runtimePreferences,
    );
    final resolvedThreads = _resolvePositiveInt(threads, tuning.threads);
    final resolvedThreadsBatch = math.max(
      resolvedThreads,
      _resolvePositiveInt(threadsBatch, tuning.threadsBatch),
    );
    final resolvedBatchSize = _resolvePositiveInt(batchSize, tuning.batchSize);
    final resolvedUbatchSize = math.min(
      resolvedBatchSize,
      _resolvePositiveInt(ubatchSize, tuning.ubatchSize),
    );
    final config = LocalModelServerConfig(
      modelPath: '$_modelsGuestDir/${model.fileName}',
      alias: resolvedAlias,
      port: resolvedPort,
      contextSize: resolvedContext,
      threads: resolvedThreads,
      threadsBatch: resolvedThreadsBatch,
      batchSize: resolvedBatchSize,
      ubatchSize: resolvedUbatchSize,
    );

    if (await _isServiceRunning()) {
      await stop();
    }

    await NativeBridge.writeRootfsFile(
      _serverConfigRootfsPath,
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );

    await NativeBridge.startLocalModelService(
      binaryPath: _binaryGuestPath,
      modelPath: config.modelPath,
      logPath: _serverLogGuestPath,
      port: config.port,
      alias: config.alias,
      contextSize: config.contextSize,
      threads: config.threads,
      threadsBatch: config.threadsBatch,
      batchSize: config.batchSize,
      ubatchSize: config.ubatchSize,
    );

    await _waitForStarted(config.port);
  }

  static Future<void> stop() async {
    final activeConfig = await _readServerConfig();
    final port = activeConfig?.port ?? defaultPort;
    try {
      await NativeBridge.stopLocalModelService();
    } finally {
      await _terminateResidualProcesses();
    }
    await _waitForStopped(port);
  }

  static Future<CustomProviderPreset> saveOrActivateProviderPreset({
    required String alias,
    required int port,
  }) async {
    final config = await ProviderConfigService.readConfig();
    final presets = List<CustomProviderPreset>.from(
        config['customPresets'] as List? ?? const []);

    String? previousProviderId;
    for (final preset in presets) {
      if (preset.providerId == localProviderId) {
        previousProviderId = preset.providerId;
        break;
      }
    }

    return ProviderConfigService.saveCustomProviderPreset(
      compatibility: CustomProviderCompatibility.openaiChatCompletions,
      apiKey: '',
      baseUrl: 'http://127.0.0.1:$port',
      modelId: alias.trim(),
      providerId: localProviderId,
      alias: alias.trim(),
      previousProviderId: previousProviderId,
    );
  }

  static String suggestFileNameFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    final segment =
        uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : '';
    final raw = segment.isEmpty ? 'model.gguf' : segment;
    return sanitizeModelFileName(raw);
  }

  @visibleForTesting
  static List<String> buildDownloadSourceUrls(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return const <String>[];
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.trim().isEmpty) {
      return <String>[trimmed];
    }

    return _buildDownloadCandidateUris(uri)
        .map((candidate) => candidate.toString())
        .toList(growable: false);
  }

  static String sanitizeModelFileName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final sanitized = trimmed
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^\.+'), '')
        .replaceAll(RegExp(r'^\-+|\-+$'), '');
    if (sanitized.isEmpty) {
      return 'model.gguf';
    }
    return sanitized.toLowerCase().endsWith('.gguf')
        ? sanitized
        : '$sanitized.gguf';
  }

  static List<LocalModelRecommendation> buildRecommendations(
    LocalModelHardwareProfile hardware,
  ) {
    final memory = hardware.memoryGiB;
    if (memory <= 0) {
      return const [
        LocalModelRecommendation(
          title: 'Recommended starting point',
          description: 'Try a 1B-3B instruct GGUF first, preferably Q4_K_M.',
        ),
      ];
    }

    if (memory < 6) {
      return const [
        LocalModelRecommendation(
          title: 'Low-memory tier',
          description:
              'Prioritize 1B-3B instruct GGUF models in Q4_K_M or Q4_0.',
        ),
        LocalModelRecommendation(
          title: 'Avoid for now',
          description:
              '7B class models will usually be too slow or fail on this device.',
        ),
      ];
    }

    if (memory < 10) {
      return const [
        LocalModelRecommendation(
          title: 'Balanced tier',
          description:
              '3B-4B instruct GGUF models in Q4_K_M are the safest default.',
        ),
        LocalModelRecommendation(
          title: 'Stretch goal',
          description:
              'Some 7B Q4 models may load, but expect slower generation.',
        ),
      ];
    }

    return const [
      LocalModelRecommendation(
        title: 'High-memory tier',
        description:
            '7B-8B instruct GGUF models in Q4_K_M are a practical target.',
      ),
      LocalModelRecommendation(
        title: 'Faster responses',
        description:
            'If latency matters, keep a smaller 3B-4B model installed too.',
      ),
    ];
  }

  static Future<LocalModelRuntimePreferences> readRuntimePreferences() async {
    final prefs = PreferencesService();
    await prefs.init();
    return LocalModelRuntimePreferences(
      maxCpuCores: prefs.localModelMaxCpuCores,
      memoryLimitMiB: prefs.localModelMemoryLimitMiB,
      performanceMode:
          _performanceModeFromString(prefs.localModelPerformanceMode),
    );
  }

  static int recommendedContextSize(
    LocalModelHardwareProfile hardware, {
    LocalModelRuntimePreferences runtimePreferences =
        const LocalModelRuntimePreferences.defaults(),
  }) {
    final effectiveMemoryGiB = _effectiveMemoryGiB(
      hardware,
      runtimePreferences: runtimePreferences,
    );
    return effectiveMemoryGiB >= 8 ? 8192 : defaultContextSize;
  }

  @visibleForTesting
  static LocalModelServerTuning recommendServerTuning({
    required LocalModelHardwareProfile hardware,
    required int modelSizeBytes,
    int contextSize = defaultContextSize,
    LocalModelRuntimePreferences runtimePreferences =
        const LocalModelRuntimePreferences.defaults(),
  }) {
    final cpuCount = _effectiveCpuCount(
      hardware,
      runtimePreferences: runtimePreferences,
    );
    final memoryGiB = _effectiveMemoryGiB(
      hardware,
      runtimePreferences: runtimePreferences,
    );
    final modelGiB =
        modelSizeBytes > 0 ? modelSizeBytes / 1024 / 1024 / 1024 : 1.0;

    var threads = _clampInt(cpuCount, 2, 16);
    if (memoryGiB < 4.5) {
      threads = _clampInt(threads, 2, math.min(cpuCount, 4));
    } else if (memoryGiB < 6.5 && modelGiB >= 1.5) {
      threads = _clampInt(threads, 2, math.min(cpuCount, 6));
    } else if (modelGiB >= 4.5) {
      threads = _clampInt(threads, 2, math.min(cpuCount, 8));
    }

    var threadsBatch = cpuCount <= threads
        ? threads
        : math.min(cpuCount, threads + (memoryGiB >= 8 ? 2 : 1));
    if (modelGiB <= 1.5 && memoryGiB >= 6) {
      threadsBatch = math.min(cpuCount, math.max(threadsBatch, threads + 1));
    }
    threadsBatch = _clampInt(threadsBatch, threads, 16);

    var batchSize = memoryGiB < 4.5
        ? 384
        : memoryGiB < 6.5
            ? 640
            : memoryGiB < 10
                ? 1024
                : 1536;

    if (modelGiB <= 0.75 && memoryGiB >= 6) {
      batchSize *= 2;
    } else if (modelGiB <= 1.5 && memoryGiB >= 8) {
      batchSize = (batchSize * 3) ~/ 2;
    } else if (modelGiB >= 4.5) {
      batchSize = math.min(batchSize, 768);
    }

    if (contextSize >= 12288) {
      batchSize = math.max(256, batchSize ~/ 2);
    } else if (contextSize >= 8192) {
      batchSize = math.max(256, (batchSize * 3) ~/ 4);
    }
    batchSize = _clampInt(batchSize, 128, 2048);

    var ubatchCap = memoryGiB < 4.5
        ? 256
        : memoryGiB < 6.5
            ? 512
            : memoryGiB < 10
                ? 1024
                : 1536;
    if (modelGiB >= 4.5) {
      ubatchCap = math.min(ubatchCap, 768);
    }

    var ubatchSize = math.min(batchSize, ubatchCap);
    if (modelGiB <= 0.75 && memoryGiB >= 8) {
      ubatchSize = math.min(batchSize, 1024);
    }
    ubatchSize = _clampInt(ubatchSize, 128, batchSize);

    switch (runtimePreferences.performanceMode) {
      case LocalModelPerformanceMode.memorySaver:
        threads = _clampInt(threads - 1, 2, cpuCount);
        threadsBatch = _clampInt(threadsBatch - 1, threads, cpuCount);
        batchSize =
            _clampInt(_roundUpToMultiple(batchSize ~/ 2, 64), 128, 2048);
        ubatchSize = _clampInt(
          _roundUpToMultiple(math.min(ubatchSize, batchSize) ~/ 2, 64),
          128,
          batchSize,
        );
        break;
      case LocalModelPerformanceMode.balanced:
        break;
      case LocalModelPerformanceMode.performance:
        threads = _clampInt(threads + 1, 2, cpuCount);
        threadsBatch = _clampInt(
          math.max(threadsBatch, threads + 1),
          threads,
          cpuCount,
        );
        batchSize = _clampInt(
          _roundUpToMultiple(((batchSize * 5) / 4).round(), 64),
          128,
          2048,
        );
        ubatchSize = _clampInt(
          _roundUpToMultiple(
              ((math.min(ubatchSize, batchSize) * 5) / 4).round(), 64),
          128,
          batchSize,
        );
        break;
    }

    return LocalModelServerTuning(
      threads: threads,
      threadsBatch: threadsBatch,
      batchSize: batchSize,
      ubatchSize: ubatchSize,
    );
  }

  static List<LocalModelCatalogEntry> searchCatalog({
    String query = '',
    String group = 'all',
    LocalModelHardwareProfile? hardware,
  }) {
    final normalizedGroup = group.trim().toLowerCase();
    final entries = modelCatalog.where((entry) {
      final groupMatch = normalizedGroup.isEmpty ||
          normalizedGroup == 'all' ||
          entry.group == normalizedGroup;
      return groupMatch && entry.matchesQuery(query);
    }).toList(growable: false);

    final memoryGiB = hardware?.memoryGiB ?? 0;
    entries.sort((left, right) {
      final leftRank = _catalogCompatibilityRank(left, memoryGiB);
      final rightRank = _catalogCompatibilityRank(right, memoryGiB);
      if (leftRank != rightRank) {
        return leftRank.compareTo(rightRank);
      }

      final memoryCompare =
          left.recommendedMemoryGiB.compareTo(right.recommendedMemoryGiB);
      if (memoryCompare != 0) {
        return memoryCompare;
      }
      return left.title.compareTo(right.title);
    });
    return entries;
  }

  static int _catalogCompatibilityRank(
    LocalModelCatalogEntry entry,
    double memoryGiB,
  ) {
    if (memoryGiB <= 0) {
      return 1;
    }
    if (memoryGiB >= entry.recommendedMemoryGiB) {
      return 0;
    }
    if (memoryGiB >= entry.minimumMemoryGiB) {
      return 1;
    }
    return 2;
  }

  static LocalModelPerformanceMode _performanceModeFromString(String value) {
    switch (value.trim()) {
      case 'memorySaver':
        return LocalModelPerformanceMode.memorySaver;
      case 'performance':
        return LocalModelPerformanceMode.performance;
      case 'balanced':
      default:
        return LocalModelPerformanceMode.balanced;
    }
  }

  static int _effectiveCpuCount(
    LocalModelHardwareProfile hardware, {
    required LocalModelRuntimePreferences runtimePreferences,
  }) {
    final detectedCpuCount = hardware.cpuCount > 0 ? hardware.cpuCount : 4;
    if (runtimePreferences.maxCpuCores <= 0) {
      return detectedCpuCount;
    }
    return _clampInt(runtimePreferences.maxCpuCores, 1, detectedCpuCount);
  }

  static double _effectiveMemoryGiB(
    LocalModelHardwareProfile hardware, {
    required LocalModelRuntimePreferences runtimePreferences,
  }) {
    final detectedMemoryGiB = hardware.memoryGiB > 0 ? hardware.memoryGiB : 6.0;
    if (runtimePreferences.memoryLimitMiB <= 0) {
      return detectedMemoryGiB;
    }
    return math.min(
      detectedMemoryGiB,
      runtimePreferences.memoryLimitMiB / 1024,
    );
  }

  static int _resolvePositiveInt(int? value, int fallback) {
    if (value != null && value > 0) {
      return value;
    }
    return fallback;
  }

  static int _clampInt(int value, int minValue, int maxValue) {
    return math.min(maxValue, math.max(minValue, value));
  }

  static int _roundUpToMultiple(int value, int multiple) {
    if (value <= 0 || multiple <= 1) {
      return value;
    }
    final remainder = value % multiple;
    return remainder == 0 ? value : value + (multiple - remainder);
  }

  static Future<LocalModelRuntimeRelease>
      _resolveLatestReleaseForCurrentArch() async {
    final arch = await NativeBridge.getArch();
    final assetPattern = _assetNamePatternForArch(arch);
    if (assetPattern == null) {
      throw Exception('Current device architecture is not supported: $arch');
    }

    try {
      final response = await http.get(
        Uri.parse(_githubApiLatestRelease),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'openclaw-termux-zh',
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
            'Failed to query llama.cpp releases (HTTP ${response.statusCode}).');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Unexpected llama.cpp release payload.');
      }

      final tagName = decoded['tag_name']?.toString().trim() ?? '';
      final assets = decoded['assets'];
      if (tagName.isEmpty || assets is! List) {
        throw Exception('Latest llama.cpp release metadata is incomplete.');
      }

      for (final asset in assets) {
        if (asset is! Map) {
          continue;
        }
        final name = asset['name']?.toString().trim() ?? '';
        final downloadUrl =
            asset['browser_download_url']?.toString().trim() ?? '';
        if (assetPattern.hasMatch(name) && downloadUrl.isNotEmpty) {
          return LocalModelRuntimeRelease(
            tagName: tagName,
            assetName: name,
            downloadUrl: downloadUrl,
          );
        }
      }
    } catch (_) {
      final fallback = _fallbackReleaseForArch(arch);
      if (fallback != null) {
        return fallback;
      }
    }

    throw Exception(
        'No Ubuntu release asset was found for architecture $arch.');
  }

  static RegExp? _assetNamePatternForArch(String arch) {
    switch (arch) {
      case 'aarch64':
        return RegExp(r'^llama-.*-bin-ubuntu-arm64\.tar\.gz$');
      case 'x86_64':
        return RegExp(r'^llama-.*-bin-ubuntu-x64\.tar\.gz$');
      default:
        return null;
    }
  }

  static LocalModelRuntimeRelease? _fallbackReleaseForArch(String arch) {
    switch (arch) {
      case 'aarch64':
        return const LocalModelRuntimeRelease(
          tagName: _fallbackReleaseTag,
          assetName: 'llama-b8763-bin-ubuntu-arm64.tar.gz',
          downloadUrl:
              'https://github.com/ggml-org/llama.cpp/releases/download/b8763/llama-b8763-bin-ubuntu-arm64.tar.gz',
        );
      case 'x86_64':
        return const LocalModelRuntimeRelease(
          tagName: _fallbackReleaseTag,
          assetName: 'llama-b8763-bin-ubuntu-x64.tar.gz',
          downloadUrl:
              'https://github.com/ggml-org/llama.cpp/releases/download/b8763/llama-b8763-bin-ubuntu-x64.tar.gz',
        );
      default:
        return null;
    }
  }

  static Future<bool> _isInstalled() async {
    try {
      final output = await NativeBridge.runInProot(
        'if [ -x ${_shellQuote(_binaryGuestPath)} ]; then echo installed; fi',
        timeout: 15,
      );
      return output.contains('installed');
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _isServiceRunning() async {
    try {
      return await NativeBridge.isLocalModelServiceRunning();
    } catch (_) {
      return false;
    }
  }

  static Future<LocalModelModuleInfo?> _readModuleInfo() async {
    try {
      final content = await NativeBridge.readRootfsFile(_moduleInfoRootfsPath);
      if (content == null || content.trim().isEmpty) {
        return null;
      }
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return LocalModelModuleInfo.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  static Future<LocalModelServerConfig?> _readServerConfig() async {
    try {
      final content =
          await NativeBridge.readRootfsFile(_serverConfigRootfsPath);
      if (content == null || content.trim().isEmpty) {
        return null;
      }
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final config = LocalModelServerConfig.fromJson(decoded);
      if (config.modelPath.isEmpty) {
        return null;
      }
      return config;
    } catch (_) {
      return null;
    }
  }

  static Future<List<LocalModelDownloadedModel>> _listModels() async {
    try {
      final filesDir = await NativeBridge.getFilesDir();
      final modelsDir = Directory('$filesDir/rootfs/ubuntu/$_modelsRootfsDir');
      if (!await modelsDir.exists()) {
        return const <LocalModelDownloadedModel>[];
      }

      final models = <LocalModelDownloadedModel>[];
      await for (final entity in modelsDir.list(followLinks: false)) {
        if (entity is! File || !entity.path.toLowerCase().endsWith('.gguf')) {
          continue;
        }
        try {
          final stat = await entity.stat();
          models.add(
            LocalModelDownloadedModel(
              fileName: entity.uri.pathSegments.last,
              path: entity.path,
              sizeBytes: stat.size,
              modifiedAt: stat.modified,
            ),
          );
        } catch (_) {
          // Ignore files that disappear during refresh.
        }
      }

      models.sort((left, right) {
        final modifiedCompare = right.modifiedAt.compareTo(left.modifiedAt);
        if (modifiedCompare != 0) {
          return modifiedCompare;
        }
        return left.fileName.compareTo(right.fileName);
      });
      return models;
    } catch (_) {
      return const <LocalModelDownloadedModel>[];
    }
  }

  static Future<LocalModelHardwareProfile> _readHardwareProfile() async {
    try {
      final output = await NativeBridge.runInProot(
        r'''
cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 0)"
mem_kib="$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null | head -n 1)"
storage_kib="$(df -Pk /root 2>/dev/null | awk 'NR==2 {print $4}' | head -n 1)"
printf '{"cpuCount":%s,"memoryKiB":%s,"freeStorageKiB":%s}\n' "${cpu_count:-0}" "${mem_kib:-0}" "${storage_kib:-0}"
''',
        timeout: 15,
      );
      final decoded = jsonDecode(output.trim());
      if (decoded is! Map<String, dynamic>) {
        return const LocalModelHardwareProfile.empty();
      }
      return LocalModelHardwareProfile(
        cpuCount: (decoded['cpuCount'] as num?)?.toInt() ?? 0,
        memoryKiB: (decoded['memoryKiB'] as num?)?.toInt() ?? 0,
        freeStorageKiB: (decoded['freeStorageKiB'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return const LocalModelHardwareProfile.empty();
    }
  }

  static Future<LocalModelRuntimeSample?> readRuntimeSample() async {
    try {
      final nativeStats = await NativeBridge.getLocalModelRuntimeStats();
      if (nativeStats != null) {
        final nativePid = (nativeStats['pid'] as num?)?.toInt() ?? 0;
        if (nativePid > 0) {
          return LocalModelRuntimeSample(
            pid: nativePid,
            rssKiB: (nativeStats['rssKiB'] as num?)?.toInt() ?? 0,
            threadCount: (nativeStats['threadCount'] as num?)?.toInt() ?? 0,
            processTicks: (nativeStats['processTicks'] as num?)?.toInt() ?? 0,
            cpuTotalTicks: (nativeStats['cpuTotalTicks'] as num?)?.toInt() ?? 0,
            sampledAt: DateTime.now(),
          );
        }
      }

      final pidFilePath = _shellQuote(_runtimePidGuestPath);
      final output = await NativeBridge.runInProot(
        '''
pid_file=$pidFilePath
cpu_total="\$(awk '/^cpu / {sum=0; for (i = 2; i <= NF; i++) sum += \$i; print sum}' /proc/stat 2>/dev/null | head -n 1)"

sample_pid() {
  pid="\$1"
  require_match="\${2:-1}"
  [ -n "\$pid" ] || return 1
  [ -r "/proc/\$pid/stat" ] || return 1

  if [ "\$require_match" != "0" ]; then
    comm="\$(cat "/proc/\$pid/comm" 2>/dev/null || true)"
    cmdline="\$(tr '\\000' ' ' < "/proc/\$pid/cmdline" 2>/dev/null || true)"

    case "\$comm \$cmdline" in
      *llama-server*|*llama.cpp/runtime/current/llama-server*|*/usr/local/bin/llama-server*)
        ;;
      *)
        return 1
        ;;
    esac
  fi

  rss_kib="\$(awk '/VmRSS/ {print \$2}' "/proc/\$pid/status" 2>/dev/null | head -n 1)"
  threads="\$(awk '/Threads/ {print \$2}' "/proc/\$pid/status" 2>/dev/null | head -n 1)"
  proc_ticks="\$(awk '{print \$14 + \$15}' "/proc/\$pid/stat" 2>/dev/null)"

  printf '{"pid":%s,"rssKiB":%s,"threadCount":%s,"processTicks":%s,"cpuTotalTicks":%s}\\n' \
    "\${pid:-0}" \
    "\${rss_kib:-0}" \
    "\${threads:-0}" \
    "\${proc_ticks:-0}" \
    "\${cpu_total:-0}"
  exit 0
}

if [ -r "\$pid_file" ]; then
  sample_pid "\$(tr -cd '0-9' < "\$pid_file" 2>/dev/null || true)" 0
fi

for proc_dir in /proc/[0-9]*; do
  pid="\${proc_dir##*/}"
  [ -r "\$proc_dir/comm" ] || continue
  comm="\$(cat "\$proc_dir/comm" 2>/dev/null || true)"
  cmdline="\$(tr '\\000' ' ' < "\$proc_dir/cmdline" 2>/dev/null || true)"
  case "\$comm \$cmdline" in
    *llama-server*|*llama.cpp/runtime/current/llama-server*|*/usr/local/bin/llama-server*)
      sample_pid "\$pid" 1
      ;;
  esac
done

printf '{}\\n'
''',
        timeout: 10,
      );
      final decoded = jsonDecode(output.trim());
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final pid = (decoded['pid'] as num?)?.toInt() ?? 0;
      if (pid <= 0) {
        return null;
      }
      return LocalModelRuntimeSample(
        pid: pid,
        rssKiB: (decoded['rssKiB'] as num?)?.toInt() ?? 0,
        threadCount: (decoded['threadCount'] as num?)?.toInt() ?? 0,
        processTicks: (decoded['processTicks'] as num?)?.toInt() ?? 0,
        cpuTotalTicks: (decoded['cpuTotalTicks'] as num?)?.toInt() ?? 0,
        sampledAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  static LocalModelRuntimeUsage? computeRuntimeUsage({
    required LocalModelRuntimeSample sample,
    LocalModelRuntimeSample? previousSample,
    required LocalModelHardwareProfile hardware,
  }) {
    double? cpuPercent;
    double? approxCoreCount;

    if (previousSample != null && previousSample.pid == sample.pid) {
      final processDelta = sample.processTicks - previousSample.processTicks;
      final cpuTotalDelta = sample.cpuTotalTicks - previousSample.cpuTotalTicks;
      final cpuCount = hardware.cpuCount > 0 ? hardware.cpuCount : 1;
      if (processDelta > 0 && cpuTotalDelta > 0) {
        cpuPercent = ((processDelta / cpuTotalDelta) * cpuCount * 100)
            .clamp(0, cpuCount * 100)
            .toDouble();
        approxCoreCount = cpuPercent / 100;
      }
    }

    return LocalModelRuntimeUsage(
      pid: sample.pid,
      rssKiB: sample.rssKiB,
      threadCount: sample.threadCount,
      cpuPercent: cpuPercent,
      approxCoreCount: approxCoreCount,
      sampledAt: sample.sampledAt,
    );
  }

  static Future<List<String>> _readRecentLogs() async {
    try {
      final content = await NativeBridge.readRootfsFile(_serverLogRootfsPath);
      if (content == null || content.trim().isEmpty) {
        return const <String>[];
      }
      final lines = const LineSplitter()
          .convert(content)
          .map((line) => line.trimRight())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
      if (lines.length <= 120) {
        return lines;
      }
      return lines.sublist(lines.length - 120);
    } catch (_) {
      return const <String>[];
    }
  }

  static Future<void> _runCommandWithLogs(
    String command, {
    required String logRootfsPath,
    required void Function(List<String> lines)? onLogChanged,
    required int timeoutSeconds,
  }) async {
    final runFuture = NativeBridge.runInProot(command, timeout: timeoutSeconds);

    var previousLines = const <String>[];
    while (true) {
      previousLines = await _emitLogUpdate(
        logRootfsPath: logRootfsPath,
        onLogChanged: onLogChanged,
        previousLines: previousLines,
      );

      final completed = await Future.any<bool>([
        runFuture.then((_) => true, onError: (_) => true),
        Future<bool>.delayed(
          const Duration(milliseconds: 700),
          () => false,
        ),
      ]);
      if (completed) {
        break;
      }
    }

    await _emitLogUpdate(
      logRootfsPath: logRootfsPath,
      onLogChanged: onLogChanged,
      previousLines: previousLines,
      force: true,
    );

    await runFuture;
  }

  static Future<List<String>> _emitLogUpdate({
    required String logRootfsPath,
    required void Function(List<String> lines)? onLogChanged,
    required List<String> previousLines,
    bool force = false,
  }) async {
    if (onLogChanged == null) {
      return previousLines;
    }
    final content = await NativeBridge.readRootfsFile(logRootfsPath);
    final lines = content == null || content.trim().isEmpty
        ? const <String>[]
        : const LineSplitter()
            .convert(content)
            .map((line) => line.trimRight())
            .where((line) => line.isNotEmpty)
            .toList(growable: false);
    if (force || !_sameLines(previousLines, lines)) {
      onLogChanged(lines);
      return lines;
    }
    return previousLines;
  }

  static bool _sameLines(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  static Future<bool> _isEndpointReachable(int port) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      try {
        final request =
            await client.getUrl(Uri.parse('http://127.0.0.1:$port/health'));
        final response =
            await request.close().timeout(const Duration(seconds: 4));
        await response.drain<void>();
        return response.statusCode >= 200 && response.statusCode < 500;
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      try {
        final socket = await Socket.connect(
          '127.0.0.1',
          port,
          timeout: const Duration(seconds: 2),
        );
        socket.destroy();
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  static Future<void> _waitForStarted(int port) async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      if (await _isEndpointReachable(port)) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 800));
    }

    final logs = await _readRecentLogs();
    final suffix =
        logs.isEmpty ? '' : ' Recent logs: ${logs.takeLast(12).join(' | ')}';
    throw Exception('llama.cpp server did not start on port $port.$suffix');
  }

  static Future<void> _waitForStopped(int port) async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(deadline)) {
      if (!await _isServiceRunning() && !await _isEndpointReachable(port)) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }
  }

  static Future<bool> isEndpointReachableForPort(int port) async {
    return _isEndpointReachable(port);
  }

  static Future<void> _terminateResidualProcesses() async {
    try {
      await NativeBridge.runInProot(
        r'''
current_pid="$$"
parent_pid="$PPID"

for proc_dir in /proc/[0-9]*; do
  pid="${proc_dir##*/}"
  [ "$pid" = "$current_pid" ] && continue
  [ "$pid" = "$parent_pid" ] && continue
  [ -r "$proc_dir/comm" ] || continue
  if [ "$(cat "$proc_dir/comm" 2>/dev/null || true)" = "llama-server" ]; then
    kill "$pid" 2>/dev/null || true
  fi
done

sleep 1

for proc_dir in /proc/[0-9]*; do
  pid="${proc_dir##*/}"
  [ "$pid" = "$current_pid" ] && continue
  [ "$pid" = "$parent_pid" ] && continue
  [ -r "$proc_dir/comm" ] || continue
  if [ "$(cat "$proc_dir/comm" 2>/dev/null || true)" = "llama-server" ]; then
    kill -9 "$pid" 2>/dev/null || true
  fi
done
''',
        timeout: 20,
      );
    } catch (_) {
      // Best effort only.
    }
  }

  static Future<void> _ensureRuntimeReady() async {
    try {
      await NativeBridge.setupDirs();
    } catch (_) {}
    try {
      await NativeBridge.writeResolv();
    } catch (_) {}
    try {
      final filesDir = await NativeBridge.getFilesDir();
      const resolvContent = 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n';

      final resolvFile = File('$filesDir/config/resolv.conf');
      if (!resolvFile.existsSync() || resolvFile.lengthSync() == 0) {
        resolvFile.parent.createSync(recursive: true);
        resolvFile.writeAsStringSync(resolvContent);
      }

      final rootfsResolv = File('$filesDir/rootfs/ubuntu/etc/resolv.conf');
      if (!rootfsResolv.existsSync() || rootfsResolv.lengthSync() == 0) {
        rootfsResolv.parent.createSync(recursive: true);
        rootfsResolv.writeAsStringSync(resolvContent);
      }
    } catch (_) {}
  }

  static Future<void> _downloadModelFile({
    required Uri url,
    required String destinationPath,
    required void Function(int received, int total) onReceiveProgress,
  }) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(hours: 4),
        sendTimeout: const Duration(seconds: 30),
        followRedirects: true,
        maxRedirects: 8,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 400,
      ),
    );

    try {
      final response = await dio.download(
        url.toString(),
        destinationPath,
        onReceiveProgress: onReceiveProgress,
        options: Options(headers: _downloadHeadersForUri(url)),
      );
      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 400) {
        throw DioException.badResponse(
          statusCode: statusCode,
          requestOptions: response.requestOptions,
          response: response,
        );
      }

      final downloadedFile = File(destinationPath);
      if (!await downloadedFile.exists() ||
          await downloadedFile.length() <= 0) {
        throw LocalModelDownloadException(
          _localized(
            '下载结束了，但模型文件没有成功写入。',
            'The download finished, but the model file was not written.',
          ),
          code: 'empty_file',
          url: url.toString(),
        );
      }
    } finally {
      dio.close(force: true);
    }
  }

  static List<Uri> _buildDownloadCandidateUris(Uri uri) {
    final candidates = <Uri>[uri];
    final host = uri.host.trim().toLowerCase();

    if (_isHuggingFaceHost(host)) {
      candidates.add(uri.replace(host: 'hf-mirror.com'));
    } else if (host == 'hf-mirror.com') {
      candidates.add(uri.replace(host: 'huggingface.co'));
    }

    final deduped = <String>{};
    return candidates
        .where((candidate) => deduped.add(candidate.toString()))
        .toList(
          growable: false,
        );
  }

  static bool _isHuggingFaceHost(String host) {
    final normalized = host.trim().toLowerCase();
    return normalized == 'huggingface.co' ||
        normalized == 'www.huggingface.co' ||
        normalized == 'hf.co';
  }

  static Map<String, String> _downloadHeadersForUri(Uri uri) {
    final headers = <String, String>{
      'Accept': 'application/octet-stream,*/*',
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36 OpenClaw',
    };

    final referer = _huggingFaceRefererForUri(uri);
    if (referer != null) {
      headers['Referer'] = referer;
    }
    return headers;
  }

  static String? _huggingFaceRefererForUri(Uri uri) {
    if (!_isHuggingFaceHost(uri.host)) {
      return null;
    }

    final segments =
        uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (segments.length < 2) {
      return null;
    }
    return 'https://huggingface.co/${segments[0]}/${segments[1]}';
  }

  static bool _shouldRetryDownload(DioException error) {
    final statusCode = error.response?.statusCode;
    if (statusCode != null) {
      return const {408, 425, 429, 500, 502, 503, 504}.contains(statusCode);
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      default:
        return false;
    }
  }

  static Duration _retryDelayFor(DioException error, int attempt) {
    final retryAfter = error.response?.headers.value('retry-after');
    final retryAfterSeconds = int.tryParse(retryAfter ?? '');
    if (retryAfterSeconds != null && retryAfterSeconds > 0) {
      final boundedSeconds = retryAfterSeconds.clamp(1, 60);
      return Duration(seconds: boundedSeconds);
    }

    final multiplier = error.response?.statusCode == 429 ? 2 : 1;
    final seconds = (attempt * 2 * multiplier).clamp(2, 12);
    return Duration(seconds: seconds);
  }

  static LocalModelDownloadException _mapDownloadFailure(
    DioException error, {
    required Uri attemptedUrl,
    required bool fallbackSource,
  }) {
    final statusCode = error.response?.statusCode;
    final sourceLabel = fallbackSource
        ? _localized('备用下载源', 'Fallback download source')
        : _localized('下载源', 'Download source');

    if (statusCode != null) {
      if (statusCode == 429) {
        return LocalModelDownloadException(
          _localized(
            '$sourceLabel 返回了 HTTP 429，当前正在限流。',
            '$sourceLabel returned HTTP 429 and is rate-limiting this request.',
          ),
          code: 'http_429',
          statusCode: statusCode,
          url: attemptedUrl.toString(),
          details: error.message,
        );
      }
      if (statusCode == 404) {
        return LocalModelDownloadException(
          _localized(
            '$sourceLabel 返回了 HTTP 404，文件可能已经不存在。',
            '$sourceLabel returned HTTP 404, so the file may no longer exist.',
          ),
          code: 'http_404',
          statusCode: statusCode,
          url: attemptedUrl.toString(),
          details: error.message,
        );
      }
      if (statusCode == 401 || statusCode == 403) {
        return LocalModelDownloadException(
          _localized(
            '$sourceLabel 返回了 HTTP $statusCode，这个链接可能需要登录或权限。',
            '$sourceLabel returned HTTP $statusCode, and this link may require authentication.',
          ),
          code: 'http_auth',
          statusCode: statusCode,
          url: attemptedUrl.toString(),
          details: error.message,
        );
      }
      if (statusCode >= 500) {
        return LocalModelDownloadException(
          _localized(
            '$sourceLabel 返回了 HTTP $statusCode，服务器暂时不稳定。',
            '$sourceLabel returned HTTP $statusCode, and the server is temporarily unavailable.',
          ),
          code: 'http_server',
          statusCode: statusCode,
          url: attemptedUrl.toString(),
          details: error.message,
        );
      }
      return LocalModelDownloadException(
        _localized(
          '$sourceLabel 返回了 HTTP $statusCode。',
          '$sourceLabel returned HTTP $statusCode.',
        ),
        code: 'http_other',
        statusCode: statusCode,
        url: attemptedUrl.toString(),
        details: error.message,
      );
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return LocalModelDownloadException(
          _localized(
            '$sourceLabel 连接超时了。',
            '$sourceLabel timed out.',
          ),
          code: 'timeout',
          url: attemptedUrl.toString(),
          details: error.message,
        );
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
        return LocalModelDownloadException(
          _localized(
            '$sourceLabel 连接失败了，请检查网络。',
            '$sourceLabel could not be reached. Please check the network connection.',
          ),
          code: 'network',
          url: attemptedUrl.toString(),
          details: error.message,
        );
      case DioExceptionType.cancel:
        return LocalModelDownloadException(
          _localized(
            '下载被取消了。',
            'The download was cancelled.',
          ),
          code: 'cancelled',
          url: attemptedUrl.toString(),
          details: error.message,
        );
      default:
        return LocalModelDownloadException(
          _localized(
            '$sourceLabel 下载失败了：${error.message}',
            '$sourceLabel failed: ${error.message}',
          ),
          code: 'unknown',
          url: attemptedUrl.toString(),
          details: error.message,
        );
    }
  }

  static LocalModelDownloadException _finalizeDownloadFailure(
    LocalModelDownloadException error, {
    required bool triedFallbackSource,
  }) {
    switch (error.code) {
      case 'http_429':
        return LocalModelDownloadException(
          _localized(
            triedFallbackSource
                ? '模型下载失败：源站现在限流了（HTTP 429），程序已经自动重试并尝试备用下载源，还是没成功。等一会儿再试就行。'
                : '模型下载失败：源站现在限流了（HTTP 429）。等一会儿再试就行。',
            triedFallbackSource
                ? 'Model download failed because the source is rate-limiting requests (HTTP 429). The app already retried and also tried the fallback source, but it still failed. Please try again later.'
                : 'Model download failed because the source is rate-limiting requests (HTTP 429). Please try again later.',
          ),
          code: error.code,
          statusCode: error.statusCode,
          url: error.url,
          details: error.details,
        );
      case 'http_404':
        return LocalModelDownloadException(
          _localized(
            '模型下载失败：这个链接已经失效了，或者文件已经被删掉了（HTTP 404）。',
            'Model download failed because the link is no longer valid or the file was removed (HTTP 404).',
          ),
          code: error.code,
          statusCode: error.statusCode,
          url: error.url,
          details: error.details,
        );
      case 'http_auth':
        return LocalModelDownloadException(
          _localized(
            '模型下载失败：这个链接可能需要登录或权限。请换一个公开可直接下载的 GGUF 链接。',
            'Model download failed because this link appears to require authentication. Please use a public direct GGUF link instead.',
          ),
          code: error.code,
          statusCode: error.statusCode,
          url: error.url,
          details: error.details,
        );
      case 'timeout':
        return LocalModelDownloadException(
          _localized(
            '模型下载失败：网络太慢，或者源站响应超时了。请换个网络或稍后再试。',
            'Model download failed because the network was too slow or the source timed out. Please try again later or switch networks.',
          ),
          code: error.code,
          statusCode: error.statusCode,
          url: error.url,
          details: error.details,
        );
      case 'network':
        return LocalModelDownloadException(
          _localized(
            '模型下载失败：当前网络连不上下载源。请先确认手机网络正常。',
            'Model download failed because the source could not be reached. Please check the phone network connection first.',
          ),
          code: error.code,
          statusCode: error.statusCode,
          url: error.url,
          details: error.details,
        );
      case 'empty_file':
        return LocalModelDownloadException(
          _localized(
            '模型下载失败：链接返回了空文件，建议换一个下载源再试。',
            'Model download failed because the source returned an empty file. Please try another download source.',
          ),
          code: error.code,
          statusCode: error.statusCode,
          url: error.url,
          details: error.details,
        );
      default:
        return LocalModelDownloadException(
          _localized(
            '模型下载失败：${error.details ?? error.message}',
            'Model download failed: ${error.details ?? error.message}',
          ),
          code: error.code,
          statusCode: error.statusCode,
          url: error.url,
          details: error.details,
        );
    }
  }

  static String _localized(String zh, String en) {
    final languageCode =
        PlatformDispatcher.instance.locale.languageCode.trim().toLowerCase();
    return languageCode.startsWith('zh') ? zh : en;
  }

  static String _formatByteCount(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }

    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }

    final digits = value >= 100 || unitIndex == 0 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
  }

  static String _buildInstallCommand(LocalModelRuntimeRelease release) {
    return '''
set -eu
log_file=${_shellQuote(_installLogGuestPath)}
download_url=${_shellQuote(release.downloadUrl)}
asset_name=${_shellQuote(release.assetName)}
version_name=${_shellQuote(release.tagName)}
module_dir=${_shellQuote('/root/.openclaw/modules/llama.cpp')}
runtime_root=${_shellQuote(_runtimeGuestDir)}
extract_root="\$runtime_root/extract"
version_dir="\$runtime_root/\$version_name"
archive_path="\$runtime_root/\$asset_name"
wrapper_path=${_shellQuote(_binaryGuestPath)}

mkdir -p "\$runtime_root" "\$module_dir/logs" ${_shellQuote('/root/.openclaw/models')} ${_shellQuote('/usr/local/bin')}
: > "\$log_file"

emit_failure_tail() {
  status="\$1"
  {
    echo "llama.cpp installation failed (exit code \$status)"
    if [ -f "\$log_file" ]; then
      echo '---- llama.cpp install log tail ----'
      tail -n 80 "\$log_file" || true
      echo '---- end of log ----'
    fi
  } >&2
}

trap 'status=\$?; trap - EXIT; if [ "\$status" -ne 0 ]; then emit_failure_tail "\$status"; fi; exit "\$status"' EXIT

log() {
  printf '[%s] %s\\n' "\$(date -Iseconds 2>/dev/null || date)" "\$1" >> "\$log_file"
}

ensure_tools() {
  if command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1; then
    return 0
  fi

  log "installing curl and tar"
  dpkg --configure -a >> "\$log_file" 2>&1 || true
  apt-get -f install -y >> "\$log_file" 2>&1 || true
  apt-get update >> "\$log_file" 2>&1
  DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl tar >> "\$log_file" 2>&1
}

log "preparing llama.cpp runtime install"
ensure_tools
rm -rf "\$extract_root" "\$version_dir"
mkdir -p "\$extract_root"

log "downloading official llama.cpp release"
curl --fail --location --retry 3 --connect-timeout 20 "\$download_url" -o "\$archive_path" >> "\$log_file" 2>&1

log "extracting release archive"
tar -xzf "\$archive_path" -C "\$extract_root" >> "\$log_file" 2>&1
source_dir="\$(find "\$extract_root" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
if [ -z "\$source_dir" ] || [ ! -x "\$source_dir/llama-server" ]; then
  echo "llama-server was not found in the extracted release archive." >&2
  exit 1
fi

mv "\$source_dir" "\$version_dir"
rm -rf "\$extract_root"
ln -sfn "\$version_dir" ${_shellQuote(_runtimeCurrentGuestDir)}

cat > "\$wrapper_path" <<'EOF'
#!/bin/sh
runtime_dir=$_runtimeCurrentGuestDir
export LD_LIBRARY_PATH="\$runtime_dir\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
exec "\$runtime_dir/llama-server" "\$@"
EOF
chmod 755 "\$wrapper_path"

log "llama.cpp runtime ready"
"\$wrapper_path" --version >> "\$log_file" 2>&1 || true
printf 'installed %s\\n' "\$version_name"
''';
  }

  static String _shellQuote(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }
}

extension on List<String> {
  Iterable<String> takeLast(int count) {
    if (length <= count) {
      return this;
    }
    return skip(length - count);
  }
}

class _TransferProgressEstimate {
  const _TransferProgressEstimate({
    required this.bytesPerSecond,
    required this.eta,
  });

  final double? bytesPerSecond;
  final Duration? eta;
}

class _TransferProgressTracker {
  _TransferProgressTracker() : _startedAt = DateTime.now();

  final DateTime _startedAt;

  _TransferProgressEstimate describe(int received, int total) {
    final elapsedMilliseconds =
        DateTime.now().difference(_startedAt).inMilliseconds;
    if (received <= 0 || elapsedMilliseconds <= 0) {
      return const _TransferProgressEstimate(
        bytesPerSecond: null,
        eta: null,
      );
    }

    final bytesPerSecond = received / (elapsedMilliseconds / 1000);
    if (bytesPerSecond <= 0) {
      return const _TransferProgressEstimate(
        bytesPerSecond: null,
        eta: null,
      );
    }

    if (total <= 0 || received >= total) {
      return _TransferProgressEstimate(
        bytesPerSecond: bytesPerSecond,
        eta: Duration.zero,
      );
    }

    final remainingSeconds = math.max(0, (total - received) / bytesPerSecond);
    return _TransferProgressEstimate(
      bytesPerSecond: bytesPerSecond,
      eta: Duration(seconds: remainingSeconds.round()),
    );
  }
}
