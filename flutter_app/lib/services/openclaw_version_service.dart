import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

import '../constants.dart';
import '../models/openclaw_install_options.dart';
import 'native_bridge.dart';

typedef OpenClawInstallProgressCallback = void Function(
  OpenClawInstallProgress progress,
);

class OpenClawReleaseInfo {
  final String version;
  final int? unpackedSizeBytes;
  final String? nodeRequirement;
  final String? tarballUrl;

  const OpenClawReleaseInfo({
    required this.version,
    this.unpackedSizeBytes,
    this.nodeRequirement,
    this.tarballUrl,
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

  String? get unpackedSizeLabel {
    final size = unpackedSizeBytes;
    if (size == null || size <= 0) {
      return null;
    }
    return OpenClawVersionService.formatBytes(size);
  }
}

class OpenClawVersionService {
  static const _packageJsonPath =
      'usr/local/lib/node_modules/openclaw/package.json';
  static const _packageRegistryEndpoint = 'https://registry.npmjs.org/openclaw';
  static const _latestReleaseEndpoint =
      'https://registry.npmjs.org/openclaw/latest';
  static const _nodePathMarker = '__OPENCLAW_NODE_PATH__';
  static const _nodeWrapper = '/root/.openclaw/node-wrapper.js';
  static const _npmCli = '/usr/local/lib/node_modules/npm/bin/npm-cli.js';
  final Dio _dio = Dio();
  OpenClawInstallProgress _lastProgress = const OpenClawInstallProgress(
    progress: 0.0,
    message: '',
  );

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
    } catch (_) {
      return const InstalledNodeRuntime();
    }
  }

  Future<String?> readInstalledNodeVersion() async {
    final runtime = await readInstalledNodeRuntime();
    return runtime.version;
  }

  Future<OpenClawReleaseInfo> fetchLatestRelease() async {
    final response = await http.get(
      Uri.parse(_latestReleaseEndpoint),
      headers: const {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw Exception('npm registry returned ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid npm registry response');
    }

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

    final response = await http.get(
      Uri.parse('$_packageRegistryEndpoint/$normalizedVersion'),
      headers: const {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw Exception('npm registry returned ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid npm registry response');
    }

    final release = OpenClawReleaseInfo.fromJson(decoded);
    if (release.version.isEmpty) {
      throw Exception('Requested version missing from registry response');
    }
    return release;
  }

  Future<List<OpenClawReleaseInfo>> fetchAvailableReleases({int? limit}) async {
    final response = await http.get(
      Uri.parse(_packageRegistryEndpoint),
      headers: const {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('npm registry returned ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid npm registry response');
    }

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
    final logSubscription = await _startLiveDetailStream(
      onProgress,
      enabled: captureLiveLogs,
    );

    try {
      try {
        await NativeBridge.setupDirs();
      } catch (_) {}
      try {
        await NativeBridge.writeResolv();
      } catch (_) {}

      final normalizedVersion = version.trim();
      if (normalizedVersion.isEmpty) {
        throw Exception('Version cannot be empty');
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

      final packageFile = File(
          '${await NativeBridge.getFilesDir()}/rootfs/ubuntu/tmp/openclaw-$normalizedVersion.tgz');
      packageFile.parent.createSync(recursive: true);
      if (packageFile.existsSync() && packageFile.lengthSync() <= 0) {
        try {
          packageFile.deleteSync();
        } catch (_) {}
      }

      final tarballUrl = release.tarballUrl?.trim();
      if (tarballUrl != null && tarballUrl.isNotEmpty) {
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
      final installCommand =
          _buildInstallCommand(packageSpecifier, installOptions);
      await _runEstimatedProgress(
        onProgress: onProgress,
        startProgress: 0.54,
        targetProgress: 0.88,
        message: 'Installing OpenClaw dependencies...',
        detail: captureLiveLogs ? 'Running npm install for OpenClaw...' : null,
        estimatedDuration: const Duration(minutes: 3),
        task: () => NativeBridge.runInProot(
          installCommand,
          timeout: 1800,
        ),
      );

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
      try {
        if (packageFile.existsSync()) {
          packageFile.deleteSync();
        }
      } catch (_) {}
      _emitProgress(
        onProgress,
        progress: 1.0,
        message: 'OpenClaw installed',
      );
    } finally {
      await logSubscription?.cancel();
    }
  }

  Future<void> ensureNodeRequirement(
    String? requirement, {
    OpenClawInstallProgressCallback? onProgress,
    double progressStart = 0.0,
    double progressEnd = 1.0,
  }) async {
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

    final minimumVersion = _minimumNodeVersion(requirement);
    final targetVersion = _selectNodeVersionForRequirement(
        minimumVersion ?? AppConstants.nodeVersion);
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
        'found: ${refreshedRuntime.version ?? 'not detected'}',
      );
    }
  }

  Future<void> _installNodeRuntime(
    String version, {
    OpenClawInstallProgressCallback? onProgress,
    double progressStart = 0.0,
    double progressEnd = 1.0,
  }) async {
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

  String _selectNodeVersionForRequirement(String minimumVersion) {
    if (compareVersions(AppConstants.nodeVersion, minimumVersion) >= 0) {
      return AppConstants.nodeVersion;
    }
    return minimumVersion;
  }

  bool _nodeSatisfiesRequirement(
      String? installedVersion, String? requirement) {
    if (installedVersion == null || installedVersion.trim().isEmpty) {
      return false;
    }

    final minimumVersion = _minimumNodeVersion(requirement);
    if (minimumVersion == null) {
      return true;
    }
    return compareVersions(installedVersion, minimumVersion) >= 0;
  }

  String? _minimumNodeVersion(String? requirement) {
    if (requirement == null || requirement.trim().isEmpty) {
      return null;
    }

    final match = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(requirement);
    return match?.group(1);
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
    final leftParts = _versionParts(left);
    final rightParts = _versionParts(right);
    final maxLength = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;

    for (var i = 0; i < maxLength; i++) {
      final leftValue = i < leftParts.length ? leftParts[i] : 0;
      final rightValue = i < rightParts.length ? rightParts[i] : 0;

      if (leftValue > rightValue) {
        return 1;
      }
      if (leftValue < rightValue) {
        return -1;
      }
    }

    return 0;
  }

  static List<int> _versionParts(String version) {
    return RegExp(r'\d+')
        .allMatches(version)
        .map((match) => int.tryParse(match.group(0) ?? '0') ?? 0)
        .toList();
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

  const InstalledNodeRuntime({
    this.path,
    this.version,
  });
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
