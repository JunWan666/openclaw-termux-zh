import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

import '../constants.dart';
import '../models/openclaw_install_options.dart';
import '../models/openclaw_version_policy.dart';
import 'bundled_runtime_service.dart';
import 'native_bridge.dart';
import 'proot_dns_service.dart';
import 'upgrade_config_guard.dart';

typedef OpenClawInstallProgressCallback = void Function(
  OpenClawInstallProgress progress,
);

class OpenClawReleaseInfo {
  final String version;
  final int? unpackedSizeBytes;
  final String? nodeRequirement;
  final String? tarballUrl;
  final OpenClawReleaseChannel channel;
  final OpenClawNodeValidationStatus nodeValidationStatus;

  const OpenClawReleaseInfo({
    required this.version,
    this.unpackedSizeBytes,
    this.nodeRequirement,
    this.tarballUrl,
    this.channel = OpenClawReleaseChannel.historical,
    this.nodeValidationStatus = OpenClawNodeValidationStatus.unknown,
  });

  factory OpenClawReleaseInfo.fromJson(Map<String, dynamic> json) {
    final dist = json['dist'];
    final engines = json['engines'];

    return OpenClawReleaseInfo(
      version: (json['version'] as String?)?.trim() ?? '',
      unpackedSizeBytes:
          dist is Map<String, dynamic> ? dist['unpackedSize'] as int? : null,
      nodeRequirement:
          engines is Map<String, dynamic> ? engines['node'] as String? : null,
      tarballUrl:
          dist is Map<String, dynamic> ? dist['tarball'] as String? : null,
    );
  }

  OpenClawReleaseInfo copyWith({
    String? version,
    int? unpackedSizeBytes,
    String? nodeRequirement,
    String? tarballUrl,
    OpenClawReleaseChannel? channel,
    OpenClawNodeValidationStatus? nodeValidationStatus,
  }) {
    return OpenClawReleaseInfo(
      version: version ?? this.version,
      unpackedSizeBytes: unpackedSizeBytes ?? this.unpackedSizeBytes,
      nodeRequirement: nodeRequirement ?? this.nodeRequirement,
      tarballUrl: tarballUrl ?? this.tarballUrl,
      channel: channel ?? this.channel,
      nodeValidationStatus: nodeValidationStatus ?? this.nodeValidationStatus,
    );
  }

  String? get unpackedSizeLabel {
    final size = unpackedSizeBytes;
    if (size == null || size <= 0) {
      return null;
    }
    return OpenClawVersionService.formatBytes(size);
  }
}

/// 统一的在线/离线版本目录。Stable 始终存在，网络最新版本只作为 Experimental。
class OpenClawReleaseCatalog {
  final List<OpenClawReleaseInfo> releases;
  final OpenClawReleaseInfo stableRelease;
  final OpenClawReleaseInfo? experimentalRelease;
  final String? warning;
  final bool hasOnlineMetadata;

  const OpenClawReleaseCatalog({
    required this.releases,
    required this.stableRelease,
    required this.experimentalRelease,
    required this.hasOnlineMetadata,
    this.warning,
  });

  bool get isOffline => !hasOnlineMetadata;
}

class OpenClawVersionService {
  static const _packageJsonPath =
      'usr/local/lib/node_modules/openclaw/package.json';
  static const _packageRegistryEndpoints = [
    'https://registry.npmjs.org/openclaw',
    'https://registry.npmmirror.com/openclaw',
  ];
  static const _nodePathMarker = '__OPENCLAW_NODE_PATH__';
  static const _nodeWrapper = '/root/.openclaw/node-wrapper.js';
  static const _npmCli = '/usr/local/lib/node_modules/npm/bin/npm-cli.js';
  final Dio _dio = Dio();
  final http.Client _httpClient;
  OpenClawInstallProgress _lastProgress = const OpenClawInstallProgress(
    progress: 0.0,
    message: '',
  );

  OpenClawVersionService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  double _clampProgress(double progress) => progress.clamp(0.0, 1.0).toDouble();

  void _emitProgress(
    OpenClawInstallProgressCallback? onProgress, {
    required double progress,
    required String message,
    String? detail,
    bool preserveDetail = false,
  }) {
    final nextDetail = preserveDetail ? _lastProgress.detail : detail;
    _lastProgress = OpenClawInstallProgress(
      progress: _clampProgress(progress),
      message: message,
      detail: nextDetail,
    );
    onProgress?.call(
      _lastProgress,
    );
  }

  Future<T> _runEstimatedProgress<T>({
    required OpenClawInstallProgressCallback? onProgress,
    required double startProgress,
    required double targetProgress,
    required String message,
    required Future<T> Function() task,
    required Duration estimatedDuration,
    String? detail,
    Duration tick = const Duration(milliseconds: 800),
  }) async {
    _emitProgress(
      onProgress,
      progress: startProgress,
      message: message,
      detail: detail,
    );

    final future = task();
    var isDone = false;
    future.whenComplete(() => isDone = true);
    final stopwatch = Stopwatch()..start();
    final durationMs = estimatedDuration.inMilliseconds <= 0
        ? 1.0
        : estimatedDuration.inMilliseconds.toDouble();
    var lastProgress = -1.0;

    while (!isDone) {
      await Future.delayed(tick);
      if (isDone) break;

      final elapsedFactor = stopwatch.elapsedMilliseconds / durationMs;
      final easedRatio =
          (1 - math.exp(-2.2 * elapsedFactor)).clamp(0.0, 1.0).toDouble();
      final currentProgress =
          startProgress + ((targetProgress - startProgress) * easedRatio);

      if ((currentProgress - lastProgress).abs() < 0.003) {
        continue;
      }
      lastProgress = currentProgress;
      _emitProgress(
        onProgress,
        progress: currentProgress,
        message: message,
        preserveDetail: true,
      );
    }

    return await future;
  }

  Future<void> _downloadWithProgress({
    required String url,
    required String destinationPath,
    required OpenClawInstallProgressCallback? onProgress,
    required double startProgress,
    required double endProgress,
    required String idleMessage,
    required String Function(
      String currentMb,
      String totalMb,
      String details,
    ) detailBuilder,
  }) async {
    _emitProgress(
      onProgress,
      progress: startProgress,
      message: idleMessage,
    );

    final tracker = _TransferProgressTracker();
    await _dio.download(
      url,
      destinationPath,
      onReceiveProgress: (received, total) {
        if (total <= 0) {
          return;
        }
        final ratio = received / total;
        final progress =
            startProgress + ((endProgress - startProgress) * ratio);
        final currentMb = (received / 1024 / 1024).toStringAsFixed(1);
        final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
        final details = tracker.describe(received, total);
        _emitProgress(
          onProgress,
          progress: progress,
          message: idleMessage,
          detail: detailBuilder(currentMb, totalMb, details),
        );
      },
    );
  }

  Future<StreamSubscription<String>?> _startLiveDetailStream(
    OpenClawInstallProgressCallback? onProgress, {
    bool enabled = true,
  }) async {
    if (!enabled) {
      return null;
    }

    return NativeBridge.setupLogStream.listen((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || _lastProgress.message.isEmpty) {
        return;
      }
      _emitProgress(
        onProgress,
        progress: _lastProgress.progress,
        message: _lastProgress.message,
        detail: trimmed,
      );
    });
  }

  String _buildInstallCommand(
    String packageSpecifier,
    OpenClawInstallOptions installOptions,
  ) {
    final envPrefix = installOptions.installEnvironment.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    final commandSegments = <String>[
      if (envPrefix.isNotEmpty) envPrefix,
      'node',
      _nodeWrapper,
      _npmCli,
      'install',
      '-g',
      ...installOptions.npmFlags,
      packageSpecifier,
    ];
    return commandSegments.join(' ');
  }

  Future<String?> readInstalledVersion() async {
    try {
      final packageJson = await NativeBridge.readRootfsFile(_packageJsonPath);
      if (packageJson == null || packageJson.trim().isEmpty) {
        return null;
      }

      final decoded = jsonDecode(packageJson);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final version = decoded['version'];
      if (version is String && version.trim().isNotEmpty) {
        return version.trim();
      }
    } catch (_) {}

    return null;
  }

  Future<InstalledNodeRuntime> readInstalledNodeRuntime() async {
    try {
      await ProotDnsService.ensureReady();
      final output = await NativeBridge.runInProot(
        'node_path="\$(command -v node 2>/dev/null || true)"\n'
        'if [ -z "\$node_path" ] && [ -x /usr/local/bin/node ]; then\n'
        '  node_path=/usr/local/bin/node\n'
        'fi\n'
        'if [ -n "\$node_path" ]; then\n'
        "  printf '$_nodePathMarker%s\\n' \"\$node_path\"\n"
        '  "\$node_path" --version\n'
        'fi\n',
        timeout: 15,
      );

      final lines = LineSplitter.split(output)
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.isEmpty) {
        return const InstalledNodeRuntime();
      }

      String? path;
      String? version;
      for (final line in lines) {
        if (line.startsWith(_nodePathMarker)) {
          path = line.replaceFirst(_nodePathMarker, '').trim();
          continue;
        }

        if (line.startsWith('v')) {
          version = line.replaceFirst(RegExp(r'^v'), '');
        }
      }

      return InstalledNodeRuntime(path: path, version: version);
    } catch (error) {
      return InstalledNodeRuntime(failure: error.toString());
    }
  }

  Future<String?> readInstalledNodeVersion() async {
    final runtime = await readInstalledNodeRuntime();
    return runtime.version;
  }

  Future<Map<String, dynamic>> _fetchRegistryJson(Iterable<Uri> endpoints,
      {String accept = 'application/json'}) async {
    Object? lastError;

    for (final endpoint in endpoints) {
      try {
        final response = await _httpClient.get(
          endpoint,
          headers: {'Accept': accept},
        ).timeout(const Duration(seconds: 20));

        if (response.statusCode != 200) {
          lastError = Exception(
            '${endpoint.host} returned ${response.statusCode}',
          );
          continue;
        }

        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        lastError = Exception('${endpoint.host} returned invalid JSON');
      } catch (error) {
        lastError = error;
      }
    }

    throw Exception('OpenClaw registry unavailable: $lastError');
  }

  Future<OpenClawReleaseInfo> fetchLatestRelease() async {
    final decoded = await _fetchRegistryJson(
      _packageRegistryEndpoints
          .map((endpoint) => Uri.parse('$endpoint/latest')),
    );

    final release = OpenClawReleaseInfo.fromJson(decoded);
    if (release.version.isEmpty) {
      throw Exception('Latest version missing from registry response');
    }
    return release;
  }

  Future<OpenClawReleaseInfo> fetchRelease(String version) async {
    final normalizedVersion = version.trim();
    if (normalizedVersion.isEmpty) {
      throw Exception('Version cannot be empty');
    }

    final encodedVersion = Uri.encodeComponent(normalizedVersion);
    final decoded = await _fetchRegistryJson(
      _packageRegistryEndpoints
          .map((endpoint) => Uri.parse('$endpoint/$encodedVersion')),
    );

    final release = OpenClawReleaseInfo.fromJson(decoded);
    if (release.version.isEmpty) {
      throw Exception('Requested version missing from registry response');
    }
    return release;
  }

  Future<List<OpenClawReleaseInfo>> fetchAvailableReleases({int? limit}) async {
    final decoded = await _fetchRegistryJson(
      _packageRegistryEndpoints.map(Uri.parse),
      accept: 'application/vnd.npm.install-v1+json',
    );

    final versions = decoded['versions'];
    if (versions is! Map<String, dynamic>) {
      throw Exception('Registry response missing versions');
    }

    final releasesByVersion = <String, OpenClawReleaseInfo>{};
    for (final value in versions.values) {
      if (value is! Map<String, dynamic>) {
        continue;
      }
      final release = OpenClawReleaseInfo.fromJson(value);
      if (release.version.isEmpty) {
        continue;
      }
      releasesByVersion[release.version] = release;
    }

    final releases = releasesByVersion.values.toList()
      ..sort((a, b) => compareVersions(b.version, a.version));

    if (limit != null && limit > 0 && releases.length > limit) {
      return releases.sublist(0, limit);
    }

    return releases;
  }

  /// 加载供 UI 使用的版本目录；网络不可用时仍返回可安装的 Stable。
  Future<OpenClawReleaseCatalog> loadReleaseCatalog({
    String? arch,
    Iterable<String> pinnedVersions = const [],
  }) async {
    final resolvedArch = arch ?? await NativeBridge.getArch();
    OpenClawReleaseInfo? latestRelease;
    List<OpenClawReleaseInfo> availableReleases = const [];
    String? warning;

    try {
      latestRelease = await fetchLatestRelease();
      try {
        availableReleases = await fetchAvailableReleases();
      } catch (error) {
        availableReleases = [latestRelease];
        warning = '$error';
      }
    } catch (error) {
      warning = '$error';
    }

    var catalogLatestRelease = latestRelease;
    if (latestRelease != null &&
        OpenClawReleasePolicy.isPrerelease(latestRelease.version)) {
      for (final release in availableReleases) {
        if (!OpenClawReleasePolicy.isPrerelease(release.version)) {
          catalogLatestRelease = release;
          break;
        }
      }
    }

    return buildReleaseCatalog(
      availableReleases: availableReleases,
      latestRelease: catalogLatestRelease,
      arch: resolvedArch,
      pinnedVersions: pinnedVersions,
      warning: warning,
      hasOnlineMetadata: latestRelease != null,
    );
  }

  /// 将 npm 元数据应用到固定通道策略，便于测试在线、离线和部分失败场景。
  static OpenClawReleaseCatalog buildReleaseCatalog({
    required Iterable<OpenClawReleaseInfo> availableReleases,
    required OpenClawReleaseInfo? latestRelease,
    required String arch,
    Iterable<String> pinnedVersions = const [],
    String? warning,
    bool hasOnlineMetadata = true,
  }) {
    final releasesByVersion = <String, OpenClawReleaseInfo>{};
    for (final release in availableReleases) {
      final version = release.version.trim();
      if (version.isNotEmpty) {
        releasesByVersion[version] = release;
      }
    }
    if (latestRelease != null && latestRelease.version.trim().isNotEmpty) {
      releasesByVersion[latestRelease.version.trim()] = latestRelease;
    }
    for (final version in pinnedVersions) {
      final normalized = version.trim();
      if (normalized.isNotEmpty) {
        releasesByVersion.putIfAbsent(
          normalized,
          () => OpenClawReleaseInfo(version: normalized),
        );
      }
    }

    releasesByVersion.putIfAbsent(
      OpenClawReleasePolicy.stableVersion,
      () => const OpenClawReleaseInfo(
        version: OpenClawReleasePolicy.stableVersion,
        nodeRequirement: OpenClawReleasePolicy.stableNodeRequirement,
      ),
    );

    final experimentalVersion = latestRelease?.version.trim();
    final orderedVersions = OpenClawReleasePolicy.orderVersions(
      releasesByVersion.keys,
      experimentalVersion: experimentalVersion,
    );
    final validatedNodeVersion = AppConstants.getNodeVersionForArch(arch);
    final releases = orderedVersions.map((version) {
      var release = releasesByVersion[version]!;
      if (version == OpenClawReleasePolicy.stableVersion &&
          (release.nodeRequirement?.trim().isEmpty ?? true)) {
        release = release.copyWith(
          nodeRequirement: OpenClawReleasePolicy.stableNodeRequirement,
        );
      }
      final channel = OpenClawReleasePolicy.channelFor(
        version,
        experimentalVersion: experimentalVersion,
      );
      final validationStatus = _validateNodeRequirement(
        release.nodeRequirement,
        validatedNodeVersion,
      );
      return release.copyWith(
        channel: channel,
        nodeValidationStatus: validationStatus,
      );
    }).toList(growable: false);

    final stableRelease = releases.firstWhere(
      (release) => release.channel == OpenClawReleaseChannel.stable,
    );
    OpenClawReleaseInfo? experimentalRelease;
    for (final release in releases) {
      if (release.channel == OpenClawReleaseChannel.experimental) {
        experimentalRelease = release;
        break;
      }
    }
    return OpenClawReleaseCatalog(
      releases: releases,
      stableRelease: stableRelease,
      experimentalRelease: experimentalRelease,
      warning: warning,
      hasOnlineMetadata: hasOnlineMetadata,
    );
  }

  static OpenClawNodeValidationStatus _validateNodeRequirement(
    String? requirement,
    String validatedNodeVersion,
  ) {
    if (requirement == null || requirement.trim().isEmpty) {
      return OpenClawNodeValidationStatus.unknown;
    }
    try {
      return NodeVersionRequirement.parse(requirement)
              .allows(validatedNodeVersion)
          ? OpenClawNodeValidationStatus.verified
          : OpenClawNodeValidationStatus.unsupported;
    } on FormatException {
      return OpenClawNodeValidationStatus.unknown;
    }
  }

  Future<void> updateToLatest({
    OpenClawReleaseInfo? latestRelease,
    OpenClawInstallProgressCallback? onProgress,
    OpenClawInstallOptions installOptions = const OpenClawInstallOptions(),
    bool captureLiveLogs = true,
  }) async {
    final release = latestRelease ?? await fetchLatestRelease();
    await installVersion(
      release.version,
      releaseInfo: release,
      installOptions: installOptions,
      onProgress: onProgress,
      captureLiveLogs: captureLiveLogs,
    );
  }

  Future<void> installVersion(
    String version, {
    OpenClawReleaseInfo? releaseInfo,
    OpenClawInstallProgressCallback? onProgress,
    OpenClawInstallOptions installOptions = const OpenClawInstallOptions(),
    bool captureLiveLogs = true,
  }) async {
    _lastProgress = const OpenClawInstallProgress(progress: 0.0, message: '');
    String? upgradeTransactionId;
    bool upgradeCommitted = false;
    final logSubscription = await _startLiveDetailStream(
      onProgress,
      enabled: captureLiveLogs,
    );

    try {
      await ProotDnsService.ensureReady();

      final normalizedVersion = version.trim();
      if (normalizedVersion.isEmpty) {
        throw Exception('Version cannot be empty');
      }

      if (await _canRestoreBundledVersion(normalizedVersion)) {
        await _restoreBundledVersion(
          normalizedVersion,
          onProgress: onProgress,
        );
        return;
      }

      _emitProgress(
        onProgress,
        progress: 0.02,
        message: 'Preparing OpenClaw package...',
      );

      final release = releaseInfo?.version == normalizedVersion
          ? releaseInfo!
          : await fetchRelease(normalizedVersion);
      await ensureNodeRequirement(
        release.nodeRequirement,
        onProgress: onProgress,
        progressStart: 0.08,
        progressEnd: 0.28,
      );

      final sourceVersion = await readInstalledVersion();
      final isVersionSwitch = sourceVersion != null &&
          !isSameVersion(
            installedVersion: sourceVersion,
            targetVersion: normalizedVersion,
          );
      final useVersionCache = isVersionSwitch &&
          await NativeBridge.hasCachedOpenClawVersion(normalizedVersion);

      final packageFile = File(
          '${await NativeBridge.getFilesDir()}/rootfs/ubuntu/tmp/openclaw-$normalizedVersion.tgz');
      packageFile.parent.createSync(recursive: true);
      if (packageFile.existsSync() && packageFile.lengthSync() <= 0) {
        try {
          packageFile.deleteSync();
        } catch (_) {}
      }

      final tarballUrl = release.tarballUrl?.trim();
      if (!useVersionCache && tarballUrl != null && tarballUrl.isNotEmpty) {
        if (!packageFile.existsSync() || packageFile.lengthSync() <= 0) {
          await _downloadWithProgress(
            url: tarballUrl,
            destinationPath: packageFile.path,
            onProgress: onProgress,
            startProgress: 0.30,
            endProgress: 0.52,
            idleMessage: 'Downloading OpenClaw package...',
            detailBuilder: (currentMb, totalMb, details) =>
                '$currentMb MB / $totalMb MB | $details',
          );
        } else {
          _emitProgress(
            onProgress,
            progress: 0.52,
            message: 'Using cached OpenClaw package...',
            detail: 'Using local OpenClaw package cache.',
          );
        }
      }

      final packageSpecifier = tarballUrl != null && tarballUrl.isNotEmpty
          ? '/tmp/${packageFile.uri.pathSegments.last}'
          : 'openclaw@$normalizedVersion';
      Map<String, dynamic> originalConfig = const {};
      if (isVersionSwitch) {
        final originalConfigContent = await NativeBridge.readRootfsFile(
          'root/.openclaw/openclaw.json',
        );
        originalConfig = UpgradeConfigGuard.decodeObject(originalConfigContent);
        try {
          await NativeBridge.stopGateway();
        } catch (_) {}
        _emitProgress(
          onProgress,
          progress: 0.53,
          message: 'Protecting existing OpenClaw data...',
        );
        final transaction = await NativeBridge.beginOpenClawUpgrade(
          sourceVersion: sourceVersion,
          targetVersion: normalizedVersion,
        );
        upgradeTransactionId = transaction['id'] as String?;
        if (upgradeTransactionId == null || upgradeTransactionId.isEmpty) {
          throw Exception('Upgrade transaction was not created');
        }
      }
      if (useVersionCache) {
        final transactionId = upgradeTransactionId;
        if (transactionId == null) {
          throw Exception(
              'Version cache restore requires an upgrade transaction');
        }
        await _runEstimatedProgress(
          onProgress: onProgress,
          startProgress: 0.54,
          targetProgress: 0.88,
          message: 'Restoring cached OpenClaw version...',
          detail:
              'Using the complete local version snapshot. npm install is skipped.',
          estimatedDuration: const Duration(seconds: 12),
          task: () => NativeBridge.restoreCachedOpenClawVersion(
            id: transactionId,
            version: normalizedVersion,
          ),
        );
      } else {
        final installCommand =
            _buildInstallCommand(packageSpecifier, installOptions);
        await _runEstimatedProgress(
          onProgress: onProgress,
          startProgress: 0.54,
          targetProgress: 0.88,
          message: 'Installing OpenClaw dependencies...',
          detail:
              captureLiveLogs ? 'Running npm install for OpenClaw...' : null,
          estimatedDuration: const Duration(minutes: 3),
          task: () => NativeBridge.runInProot(
            installCommand,
            timeout: 1800,
          ),
        );
      }

      _emitProgress(
        onProgress,
        progress: 0.92,
        message: 'Creating bin wrappers...',
      );
      await NativeBridge.createBinWrappers('openclaw');

      _emitProgress(
        onProgress,
        progress: 0.96,
        message: 'Verifying OpenClaw...',
      );
      await NativeBridge.runInProot('openclaw --version', timeout: 30);
      final installedVersion = await readInstalledVersion();
      if (installedVersion == null ||
          !isSameVersion(
            installedVersion: installedVersion,
            targetVersion: normalizedVersion,
          )) {
        throw Exception(
          'Installed version mismatch. Expected $normalizedVersion, '
          'found ${installedVersion ?? 'unknown'}',
        );
      }

      if (upgradeTransactionId != null) {
        await NativeBridge.updateOpenClawUpgrade(
          id: upgradeTransactionId,
          phase: 'packageInstalled',
          detailsJson: jsonEncode({'installedVersion': installedVersion}),
        );
        var doctorLintCompleted = false;
        var doctorFixApplied = false;
        if (compareVersions(normalizedVersion, '2026.7.0') >= 0) {
          final preDoctorContent = await NativeBridge.readRootfsFile(
            'root/.openclaw/openclaw.json',
          );
          final preDoctorConfig = UpgradeConfigGuard.decodeObject(
            preDoctorContent,
          );
          final normalizedPreDoctor =
              UpgradeConfigGuard.normalizeProviderConfiguration(
            preDoctorConfig,
          );
          if (jsonEncode(normalizedPreDoctor) != jsonEncode(preDoctorConfig)) {
            await NativeBridge.writeRootfsFile(
              'root/.openclaw/openclaw.json',
              const JsonEncoder.withIndent('  ').convert(normalizedPreDoctor),
            );
          }
          _emitProgress(
            onProgress,
            progress: 0.97,
            message: 'Checking migrated configuration...',
          );
          final lintOutput = await NativeBridge.runInProot(
            "set +e; doctor_output=\$(NODE_OPTIONS='--require "
            "/root/.openclaw/bionic-bypass.js' openclaw doctor --lint "
            "--json 2>&1); doctor_status=\$?; printf '%s\\n' "
            '"\$doctor_output"; if [ "\$doctor_status" -gt 1 ]; then '
            'exit "\$doctor_status"; fi',
            timeout: 180,
          );
          doctorLintCompleted = true;
          final needsFix = UpgradeConfigGuard.doctorNeedsFix(lintOutput);
          if (needsFix) {
            await NativeBridge.runInProot(
              "NODE_OPTIONS='--require /root/.openclaw/bionic-bypass.js' "
              'openclaw doctor --fix --non-interactive --yes',
              timeout: 300,
            );
            doctorFixApplied = true;
          }
        }
        await NativeBridge.updateOpenClawUpgrade(
          id: upgradeTransactionId,
          phase: 'doctorChecked',
          detailsJson: jsonEncode({
            'doctorLintCompleted': doctorLintCompleted,
            'doctorFixApplied': doctorFixApplied,
          }),
        );

        final migratedContent = await NativeBridge.readRootfsFile(
          'root/.openclaw/openclaw.json',
        );
        final migratedConfig = UpgradeConfigGuard.decodeObject(migratedContent);
        final mergedConfig = UpgradeConfigGuard.normalizeProviderConfiguration(
          UpgradeConfigGuard.mergePreservingUserValues(
            originalConfig,
            migratedConfig,
          ),
        );
        final configChanges = UpgradeConfigGuard.describeChanges(
          originalConfig,
          mergedConfig,
        );
        if (jsonEncode(mergedConfig) != jsonEncode(migratedConfig)) {
          await NativeBridge.writeRootfsFile(
            'root/.openclaw/openclaw.json',
            const JsonEncoder.withIndent('  ').convert(mergedConfig),
          );
        }
        await NativeBridge.runInProot(
          "NODE_OPTIONS='--require /root/.openclaw/bionic-bypass.js' "
          'openclaw config validate --json',
          timeout: 180,
        );
        final serializedChanges = configChanges
            .map((change) => {
                  'path': change.path,
                  'kind': change.kind,
                  'summary': change.summary,
                })
            .toList(growable: false);
        await NativeBridge.updateOpenClawUpgrade(
          id: upgradeTransactionId,
          phase: 'configMerged',
          detailsJson: jsonEncode({'configChanges': serializedChanges}),
        );

        final validation =
            await NativeBridge.validateOpenClawUpgrade(upgradeTransactionId);
        if (validation['valid'] != true) {
          throw Exception(
            'Protected upgrade paths are missing: ${validation['missing']}',
          );
        }
        await NativeBridge.updateOpenClawUpgrade(
          id: upgradeTransactionId,
          phase: 'verified',
          detailsJson: jsonEncode({'protectedPathsValid': true}),
        );
        final report = jsonEncode({
          'sourceVersion': sourceVersion,
          'targetVersion': normalizedVersion,
          'doctorLintCompleted': doctorLintCompleted,
          'doctorFixApplied': doctorFixApplied,
          'configChanges': serializedChanges,
        });
        await NativeBridge.commitOpenClawUpgrade(
          id: upgradeTransactionId,
          reportJson: report,
        );
        upgradeCommitted = true;
      }
      // Keep the downloaded version archive. A later 3.23 -> 7.x switch can
      // reuse it without downloading the same OpenClaw release again. npm's
      // cache only stores dependency artifacts; it is not a replacement for
      // this top-level package archive.
      try {
        await NativeBridge.trimNpmCache();
      } catch (_) {}
      _emitProgress(
        onProgress,
        progress: 1.0,
        message: 'OpenClaw installed',
      );
    } catch (_) {
      if (upgradeTransactionId != null && !upgradeCommitted) {
        try {
          await NativeBridge.rollbackOpenClawUpgrade(upgradeTransactionId);
        } catch (_) {}
      }
      rethrow;
    } finally {
      await logSubscription?.cancel();
    }
  }

  Future<bool> _canRestoreBundledVersion(String version) async {
    try {
      final manifest = await BundledRuntimeService().loadManifest();
      return isSameVersion(
        installedVersion: manifest.openclawVersion,
        targetVersion: version,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _restoreBundledVersion(
    String version, {
    OpenClawInstallProgressCallback? onProgress,
  }) async {
    final bundledRuntime = BundledRuntimeService();
    final manifest = await bundledRuntime.loadManifest();
    String? transactionId;

    try {
      _emitProgress(
        onProgress,
        progress: 0.05,
        message: 'Preparing bundled OpenClaw $version...',
        detail:
            'Using the runtime included in this APK; no download is needed.',
      );
      try {
        await NativeBridge.stopGateway();
      } catch (_) {}

      await NativeBridge.recoverInterruptedRootfsInstall();
      final sourceVersion = await readInstalledVersion();
      if (sourceVersion == null || sourceVersion.isEmpty) {
        throw Exception('Current OpenClaw version is unavailable');
      }
      final transaction = await NativeBridge.beginOpenClawUpgrade(
        sourceVersion: sourceVersion,
        targetVersion: version,
      );
      transactionId = transaction['id'] as String?;
      if (transactionId == null || transactionId.isEmpty) {
        throw Exception('Bundled downgrade transaction was not created');
      }

      _emitProgress(
        onProgress,
        progress: 0.22,
        message: 'Protecting existing OpenClaw data...',
      );

      await _runEstimatedProgress(
        onProgress: onProgress,
        startProgress: 0.30,
        targetProgress: 0.88,
        message: 'Restoring bundled OpenClaw $version...',
        detail: 'Keeping configuration, agents, workspace, skills, and memory.',
        estimatedDuration: const Duration(seconds: 20),
        task: () => NativeBridge.restoreBundledOpenClawPackage(
          bundledRuntime.assetPathFor(manifest),
        ),
      );

      await NativeBridge.createBinWrappers('openclaw', force: true);
      final restoredVersion = await readInstalledVersion();
      if (!isSameVersion(
        installedVersion: restoredVersion,
        targetVersion: version,
      )) {
        throw Exception(
          'Bundled version verification failed. Expected $version, '
          'found ${restoredVersion ?? 'unknown'}',
        );
      }
      await NativeBridge.runInProot('openclaw --version', timeout: 30);
      await NativeBridge.updateOpenClawUpgrade(
        id: transactionId,
        phase: 'packageInstalled',
        detailsJson: jsonEncode({'installedVersion': restoredVersion}),
      );
      final validation = await NativeBridge.validateOpenClawUpgrade(
        transactionId,
      );
      if (validation['valid'] != true) {
        throw Exception(
          'Protected downgrade paths are missing: ${validation['missing']}',
        );
      }
      await NativeBridge.updateOpenClawUpgrade(
        id: transactionId,
        phase: 'verified',
        detailsJson: jsonEncode({'protectedPathsValid': true}),
      );
      await NativeBridge.commitOpenClawUpgrade(
        id: transactionId,
        reportJson: jsonEncode({
          'sourceVersion': sourceVersion,
          'targetVersion': restoredVersion,
          'source': 'bundled-runtime-package',
        }),
      );
      transactionId = null;

      _emitProgress(
        onProgress,
        progress: 1,
        message: 'Bundled OpenClaw $version restored',
        detail: 'Completed locally without downloading npm packages.',
      );
    } catch (_) {
      if (transactionId != null) {
        try {
          await NativeBridge.rollbackOpenClawUpgrade(transactionId);
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> ensureNodeRequirement(
    String? requirement, {
    OpenClawInstallProgressCallback? onProgress,
    double progressStart = 0.0,
    double progressEnd = 1.0,
  }) async {
    await ProotDnsService.ensureReady();
    _emitProgress(
      onProgress,
      progress: progressStart,
      message: 'Checking Node.js requirement...',
    );
    final installedRuntime = await readInstalledNodeRuntime();
    if (_nodeSatisfiesRequirement(installedRuntime.version, requirement)) {
      _emitProgress(
        onProgress,
        progress: progressEnd,
        message: 'Node.js requirement satisfied',
      );
      return;
    }

    final arch = await NativeBridge.getArch();
    final parsedRequirement = NodeVersionRequirement.parse(requirement);
    final validatedVersions = [AppConstants.getNodeVersionForArch(arch)];
    final targetVersion =
        parsedRequirement.selectHighestAllowed(validatedVersions);
    if (targetVersion == null) {
      throw Exception(
        'No validated Node.js runtime for $arch satisfies '
        '${requirement ?? 'the requested OpenClaw release'}. '
        'Validated candidates: ${validatedVersions.join(', ')}.',
      );
    }
    await _installNodeRuntime(
      targetVersion,
      onProgress: onProgress,
      progressStart: progressStart,
      progressEnd: progressEnd,
    );

    final refreshedRuntime = await readInstalledNodeRuntime();
    if (!_nodeSatisfiesRequirement(refreshedRuntime.version, requirement)) {
      throw Exception(
        'Node.js update incomplete. Required: ${requirement ?? 'unknown'}, '
        'found: ${refreshedRuntime.diagnosticDescription}',
      );
    }
  }

  Future<void> _installNodeRuntime(
    String version, {
    OpenClawInstallProgressCallback? onProgress,
    double progressStart = 0.0,
    double progressEnd = 1.0,
  }) async {
    await ProotDnsService.ensureReady();
    final arch = await NativeBridge.getArch();
    final filesDir = await NativeBridge.getFilesDir();
    final tarPath = '$filesDir/tmp/nodejs-$version.tar.xz';
    final tarUrl = AppConstants.getNodeTarballUrlForVersion(arch, version);
    final assetPath = AppConstants.bundledBootstrapAssetPathForUrl(tarUrl);

    final tarFile = File(tarPath);
    if (tarFile.existsSync()) {
      if (tarFile.lengthSync() <= 0) {
        try {
          tarFile.deleteSync();
        } catch (_) {}
      }
    }

    var usedLocalArchive = tarFile.existsSync() && tarFile.lengthSync() > 0;
    if (!usedLocalArchive) {
      try {
        _emitProgress(
          onProgress,
          progress: progressStart,
          message: 'Using bundled Node.js $version package...',
          detail: 'Using packaged Node.js archive.',
        );
        await NativeBridge.copyBundledAssetToFile(
          assetPath: assetPath,
          destinationPath: tarPath,
        );
        usedLocalArchive = true;
      } catch (_) {}
    }

    if (!usedLocalArchive) {
      await _downloadWithProgress(
        url: tarUrl,
        destinationPath: tarPath,
        onProgress: onProgress,
        startProgress: progressStart,
        endProgress: progressStart + ((progressEnd - progressStart) * 0.65),
        idleMessage: 'Downloading Node.js $version...',
        detailBuilder: (currentMb, totalMb, details) =>
            '$currentMb MB / $totalMb MB | $details',
      );
    }

    try {
      await _runEstimatedProgress(
        onProgress: onProgress,
        startProgress: progressStart + ((progressEnd - progressStart) * 0.70),
        targetProgress: progressStart + ((progressEnd - progressStart) * 0.90),
        message: 'Extracting Node.js...',
        detail: 'Preparing Node.js files...',
        estimatedDuration: const Duration(seconds: 20),
        task: () => NativeBridge.extractNodeTarball(tarPath),
      );
    } catch (error) {
      if (!usedLocalArchive) {
        rethrow;
      }
      try {
        tarFile.deleteSync();
      } catch (_) {}
      await _downloadWithProgress(
        url: tarUrl,
        destinationPath: tarPath,
        onProgress: onProgress,
        startProgress: progressStart,
        endProgress: progressStart + ((progressEnd - progressStart) * 0.65),
        idleMessage: 'Bundled Node.js $version failed, downloading online...',
        detailBuilder: (currentMb, totalMb, details) =>
            '$currentMb MB / $totalMb MB | $details',
      );
      await _runEstimatedProgress(
        onProgress: onProgress,
        startProgress: progressStart + ((progressEnd - progressStart) * 0.70),
        targetProgress: progressStart + ((progressEnd - progressStart) * 0.90),
        message: 'Extracting Node.js...',
        detail: 'Preparing Node.js files...',
        estimatedDuration: const Duration(seconds: 20),
        task: () => NativeBridge.extractNodeTarball(tarPath),
      );
    }

    _emitProgress(
      onProgress,
      progress: progressStart + ((progressEnd - progressStart) * 0.95),
      message: 'Verifying Node.js...',
    );
    await NativeBridge.runInProot(
      'node --version && node $_nodeWrapper $_npmCli --version',
      timeout: 30,
    );
    _emitProgress(
      onProgress,
      progress: progressEnd,
      message: 'Node.js installed',
    );
  }

  bool _nodeSatisfiesRequirement(
      String? installedVersion, String? requirement) {
    return nodeVersionSatisfiesRequirement(installedVersion, requirement);
  }

  static bool nodeVersionSatisfiesRequirement(
    String? installedVersion,
    String? requirement,
  ) {
    if (installedVersion == null || installedVersion.trim().isEmpty) {
      return false;
    }

    try {
      return NodeVersionRequirement.parse(requirement).allows(installedVersion);
    } on FormatException {
      return false;
    }
  }

  static bool isUpdateAvailable({
    required String? installedVersion,
    required String latestVersion,
  }) {
    if (installedVersion == null || installedVersion.trim().isEmpty) {
      return true;
    }

    return compareVersions(latestVersion, installedVersion) > 0;
  }

  static bool isSameVersion({
    required String? installedVersion,
    required String? targetVersion,
  }) {
    if (installedVersion == null ||
        installedVersion.trim().isEmpty ||
        targetVersion == null ||
        targetVersion.trim().isEmpty) {
      return false;
    }

    return compareVersions(installedVersion, targetVersion) == 0;
  }

  static int compareVersions(String left, String right) {
    return OpenClawReleasePolicy.compareVersions(left, right);
  }

  static String formatBytes(int bytes) {
    final mb = bytes / 1024 / 1024;
    if (mb < 100) {
      return '~${mb.toStringAsFixed(1)} MB';
    }
    return '~${mb.toStringAsFixed(0)} MB';
  }
}

class InstalledNodeRuntime {
  final String? path;
  final String? version;
  final String? failure;

  const InstalledNodeRuntime({
    this.path,
    this.version,
    this.failure,
  });

  String get diagnosticDescription {
    if (version != null && version!.isNotEmpty) return version!;
    if (failure != null && failure!.isNotEmpty) {
      return 'execution failed: $failure';
    }
    if (path != null && path!.isNotEmpty) {
      return 'binary found at $path but produced no version output';
    }
    return 'node binary not found';
  }
}

class OpenClawInstallProgress {
  final double progress;
  final String message;
  final String? detail;

  const OpenClawInstallProgress({
    required this.progress,
    required this.message,
    this.detail,
  });
}

class _TransferProgressTracker {
  final Stopwatch _stopwatch = Stopwatch()..start();

  String describe(int received, int total) {
    final elapsedSeconds =
        (_stopwatch.elapsedMilliseconds / 1000).clamp(0.001, double.infinity);
    final bytesPerSecond = received / elapsedSeconds;
    final remainingBytes = math.max(0, total - received);
    final etaSeconds =
        bytesPerSecond <= 0 ? 0 : (remainingBytes / bytesPerSecond).round();
    return '${_formatSpeed(bytesPerSecond)} | ETA ${_formatEta(etaSeconds)}';
  }

  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond >= 1024 * 1024) {
      return '${(bytesPerSecond / 1024 / 1024).toStringAsFixed(1)} MB/s';
    }
    return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
  }

  String _formatEta(int seconds) {
    final safeSeconds = math.max(0, seconds);
    final minutes = safeSeconds ~/ 60;
    final remainingSeconds = safeSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
