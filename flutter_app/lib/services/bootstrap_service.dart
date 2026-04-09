import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:dio/dio.dart';
import '../constants.dart';
import '../l10n/app_localizations.dart';
import '../models/openclaw_install_options.dart';
import '../models/setup_state.dart';
import 'install_status_message_formatter.dart';
import 'native_bridge.dart';
import 'openclaw_version_service.dart';

class BootstrapService {
  final Dio _dio = Dio();
  final OpenClawVersionService _openClawVersionService =
      OpenClawVersionService();
  SetupState _lastSetupState = const SetupState();

  AppLocalizations get _notificationL10n =>
      AppLocalizations(PlatformDispatcher.instance.locale);

  void _updateSetupNotification(String text, {int progress = -1}) {
    try {
      NativeBridge.updateSetupNotification(text, progress: progress);
    } catch (_) {}
  }

  void _stopSetupService() {
    try {
      NativeBridge.stopSetupService();
    } catch (_) {}
  }

  double _clampProgress(double progress) => progress.clamp(0.0, 1.0).toDouble();

  double _overallProgressFor(SetupStep step, double stepProgress) {
    final progress = _clampProgress(stepProgress);
    switch (step) {
      case SetupStep.checkingStatus:
        return progress * 0.05;
      case SetupStep.downloadingRootfs:
        return 0.05 + (progress * 0.25);
      case SetupStep.extractingRootfs:
        return 0.30 + (progress * 0.15);
      case SetupStep.installingNode:
        return 0.45 + (progress * 0.35);
      case SetupStep.installingOpenClaw:
        return 0.80 + (progress * 0.18);
      case SetupStep.configuringBypass:
        return 0.98 + (progress * 0.02);
      case SetupStep.complete:
        return 1.0;
      case SetupStep.error:
        return 0.0;
    }
  }

  String _formatPercent(double progress, {int digits = 1}) =>
      '${(_clampProgress(progress) * 100).toStringAsFixed(digits)}%';

  bool _statusFlag(Map<String, dynamic> status, String key) =>
      status[key] == true;

  Future<bool> _isInstalledNodeUsable() async {
    try {
      const wrapper = '/root/.openclaw/node-wrapper.js';
      const npmCli = '/usr/local/lib/node_modules/npm/bin/npm-cli.js';
      await NativeBridge.runInProot(
        'node --version && node $wrapper $npmCli --version',
        timeout: 30,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isInstalledOpenClawUsable() async {
    try {
      await NativeBridge.runInProot('openclaw --version', timeout: 30);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<_PreparedArchiveSource> _prepareBundledOrCachedArchive({
    required String assetPath,
    required String destinationPath,
  }) async {
    final file = File(destinationPath);
    if (file.existsSync() && file.lengthSync() > 0) {
      return _PreparedArchiveSource.cached;
    }
    if (file.existsSync()) {
      try {
        file.deleteSync();
      } catch (_) {}
    }

    try {
      await NativeBridge.copyBundledAssetToFile(
        assetPath: assetPath,
        destinationPath: destinationPath,
      );
      if (file.existsSync() && file.lengthSync() > 0) {
        return _PreparedArchiveSource.bundled;
      }
    } catch (_) {
      return _PreparedArchiveSource.none;
    }

    return _PreparedArchiveSource.none;
  }

  Future<void> _downloadStepArchive({
    required String url,
    required String destinationPath,
    required void Function(SetupState) onProgress,
    required SetupStep step,
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
      onProgress: onProgress,
      step: step,
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
        final downloadRatio = received / total;
        final progress =
            startProgress + ((endProgress - startProgress) * downloadRatio);
        final currentMb = (received / 1024 / 1024).toStringAsFixed(1);
        final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
        final details = tracker.describe(received, total);
        _emitProgress(
          onProgress: onProgress,
          step: step,
          progress: progress,
          message: idleMessage,
          detail: detailBuilder(currentMb, totalMb, details),
        );
      },
    );
  }

  Future<String> _selectUbuntuMirror(String arch) async {
    final candidates = AppConstants.ubuntuMirrorCandidates(arch);
    const releasePath = '/dists/${AppConstants.ubuntuCodename}/Release';
    final checks = candidates.map((baseUrl) async {
      final stopwatch = Stopwatch()..start();
      try {
        final response = await _dio.get<String>(
          '$baseUrl$releasePath',
          options: Options(
            responseType: ResponseType.plain,
            sendTimeout: const Duration(seconds: 4),
            receiveTimeout: const Duration(seconds: 4),
          ),
        );
        if ((response.statusCode ?? 500) >= 200 &&
            (response.statusCode ?? 500) < 300) {
          return _MirrorProbeResult(baseUrl, stopwatch.elapsedMilliseconds);
        }
      } catch (_) {}
      return null;
    });

    final results = (await Future.wait(checks))
        .whereType<_MirrorProbeResult>()
        .toList()
      ..sort((a, b) => a.elapsedMs.compareTo(b.elapsedMs));

    if (results.isNotEmpty) {
      return results.first.baseUrl;
    }
    return candidates.last;
  }

  Future<void> _configureUbuntuMirror(String arch) async {
    final selectedMirror = await _selectUbuntuMirror(arch);
    await NativeBridge.writeRootfsFile(
      'etc/apt/sources.list',
      AppConstants.buildUbuntuSourcesList(selectedMirror),
    );
  }

  void _emitProgress({
    required void Function(SetupState) onProgress,
    required SetupStep step,
    required double progress,
    required String message,
    String? detail,
    bool preserveDetail = false,
    String? notificationText,
    bool updateNotification = true,
  }) {
    final clampedProgress = _clampProgress(progress);
    final nextDetail = preserveDetail ? _lastSetupState.detail : detail;
    _lastSetupState = SetupState(
      step: step,
      progress: clampedProgress,
      message: message,
      detail: nextDetail,
    );
    onProgress(_lastSetupState);
    if (!updateNotification) {
      return;
    }
    final overallProgress = _overallProgressFor(step, clampedProgress);
    final localizedMessage =
        InstallStatusMessageFormatter.localize(_notificationL10n, message);
    _updateSetupNotification(
      '$localizedMessage ${_formatPercent(overallProgress)}',
      progress: (overallProgress * 100).round(),
    );
  }

  Future<T> _runEstimatedProgress<T>({
    required void Function(SetupState) onProgress,
    required SetupStep step,
    required double startProgress,
    required double targetProgress,
    required String message,
    required Future<T> Function() task,
    required Duration estimatedDuration,
    String? detail,
    Duration tick = const Duration(milliseconds: 800),
  }) async {
    _emitProgress(
      onProgress: onProgress,
      step: step,
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
      final overallProgress = _overallProgressFor(step, currentProgress);
      _emitProgress(
        onProgress: onProgress,
        step: step,
        progress: currentProgress,
        message: message,
        preserveDetail: true,
        notificationText: '$message ${_formatPercent(overallProgress)}',
      );
    }

    return await future;
  }

  Future<SetupState> checkStatus() async {
    try {
      final complete = await NativeBridge.isBootstrapComplete();
      if (complete) {
        return const SetupState(
          step: SetupStep.complete,
          progress: 1.0,
          message: 'Setup complete',
        );
      }
      return const SetupState(
        step: SetupStep.checkingStatus,
        progress: 0.0,
        message: 'Setup required',
      );
    } catch (e) {
      return SetupState(
        step: SetupStep.error,
        error: 'Failed to check status: $e',
      );
    }
  }

  Future<void> runFullSetup({
    required void Function(SetupState) onProgress,
    OpenClawReleaseInfo? selectedOpenClawRelease,
    OpenClawInstallOptions installOptions = const OpenClawInstallOptions(),
  }) async {
    _lastSetupState = const SetupState();
    final logSubscription = NativeBridge.setupLogStream.listen((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || _lastSetupState.message.isEmpty) {
        return;
      }
      _emitProgress(
        onProgress: onProgress,
        step: _lastSetupState.step,
        progress: _lastSetupState.progress,
        message: _lastSetupState.message,
        detail: trimmed,
        updateNotification: false,
      );
    });

    try {
      // Start foreground service to keep app alive during setup
      try {
        await NativeBridge.startSetupService();
      } catch (_) {} // Non-fatal if service fails to start

      // Step 0: Setup directories
      _emitProgress(
        onProgress: onProgress,
        step: SetupStep.checkingStatus,
        progress: 0.4,
        message: 'Setting up directories...',
        notificationText: 'Setting up directories... 2.0%',
      );
      try {
        await NativeBridge.setupDirs();
      } catch (_) {}
      try {
        await NativeBridge.writeResolv();
      } catch (_) {}

      // Step 1: Download rootfs
      final arch = await NativeBridge.getArch();
      final rootfsUrl = AppConstants.getRootfsUrl(arch);
      final filesDir = await NativeBridge.getFilesDir();

      // Direct Dart fallback: ensure config dir + resolv.conf exist (#40).
      const resolvContent = 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n';
      try {
        final configDir = '$filesDir/config';
        final resolvFile = File('$configDir/resolv.conf');
        if (!resolvFile.existsSync()) {
          Directory(configDir).createSync(recursive: true);
          resolvFile.writeAsStringSync(resolvContent);
        }
        // Also write into rootfs /etc/ so DNS works even if bind-mount fails
        final rootfsResolv = File('$filesDir/rootfs/ubuntu/etc/resolv.conf');
        if (!rootfsResolv.existsSync()) {
          rootfsResolv.parent.createSync(recursive: true);
          rootfsResolv.writeAsStringSync(resolvContent);
        }
      } catch (_) {}
      final bootstrapStatus = await NativeBridge.getBootstrapStatus();
      final rootfsReady = _statusFlag(bootstrapStatus, 'rootfsExists') &&
          _statusFlag(bootstrapStatus, 'binBashExists');
      final tarPath = '$filesDir/tmp/ubuntu-rootfs.tar.gz';
      final rootfsAssetPath =
          AppConstants.bundledBootstrapAssetPathForUrl(rootfsUrl);

      if (rootfsReady) {
        _emitProgress(
          onProgress: onProgress,
          step: SetupStep.extractingRootfs,
          progress: 1.0,
          message: 'Ubuntu rootfs already available',
          detail: 'Reusing previously extracted rootfs.',
          notificationText: 'Ubuntu rootfs ready 45.0%',
        );
      } else {
        final rootfsSource = await _prepareBundledOrCachedArchive(
          assetPath: rootfsAssetPath,
          destinationPath: tarPath,
        );
        final rootfsFromLocal = rootfsSource != _PreparedArchiveSource.none;
        if (rootfsSource == _PreparedArchiveSource.bundled) {
          _emitProgress(
            onProgress: onProgress,
            step: SetupStep.downloadingRootfs,
            progress: 1.0,
            message: 'Using bundled Ubuntu rootfs package...',
            detail: 'Using packaged Ubuntu rootfs archive.',
            notificationText: 'Using bundled Ubuntu rootfs package... 30.0%',
          );
        } else if (rootfsSource == _PreparedArchiveSource.cached) {
          _emitProgress(
            onProgress: onProgress,
            step: SetupStep.downloadingRootfs,
            progress: 1.0,
            message: 'Using cached Ubuntu rootfs package...',
            detail: 'Reusing local Ubuntu rootfs archive cache.',
            notificationText: 'Using cached Ubuntu rootfs package... 30.0%',
          );
        } else {
          await _downloadStepArchive(
            url: rootfsUrl,
            destinationPath: tarPath,
            onProgress: onProgress,
            step: SetupStep.downloadingRootfs,
            startProgress: 0.0,
            endProgress: 1.0,
            idleMessage: 'Downloading Ubuntu rootfs...',
            detailBuilder: (currentMb, totalMb, details) =>
                '$currentMb MB / $totalMb MB | $details',
          );
        }

        try {
          await _runEstimatedProgress(
            onProgress: onProgress,
            step: SetupStep.extractingRootfs,
            startProgress: 0.02,
            targetProgress: 0.92,
            message: 'Extracting rootfs (this takes a while)...',
            estimatedDuration: const Duration(minutes: 2),
            task: () => NativeBridge.extractRootfs(tarPath),
          );
        } catch (error) {
          if (!rootfsFromLocal) {
            rethrow;
          }
          try {
            File(tarPath).deleteSync();
          } catch (_) {}
          await _downloadStepArchive(
            url: rootfsUrl,
            destinationPath: tarPath,
            onProgress: onProgress,
            step: SetupStep.downloadingRootfs,
            startProgress: 0.0,
            endProgress: 1.0,
            idleMessage: 'Local rootfs cache failed, downloading online...',
            detailBuilder: (currentMb, totalMb, details) =>
                '$currentMb MB / $totalMb MB | $details',
          );
          await _runEstimatedProgress(
            onProgress: onProgress,
            step: SetupStep.extractingRootfs,
            startProgress: 0.02,
            targetProgress: 0.92,
            message: 'Extracting rootfs (this takes a while)...',
            estimatedDuration: const Duration(minutes: 2),
            task: () => NativeBridge.extractRootfs(tarPath),
          );
        }
        _emitProgress(
          onProgress: onProgress,
          step: SetupStep.extractingRootfs,
          progress: 1.0,
          message: 'Rootfs extracted',
          notificationText: 'Rootfs extracted 45.0%',
        );
      }

      // Install bionic bypass + cwd-fix + node-wrapper BEFORE using node.
      // The wrapper patches process.cwd() which returns ENOSYS in proot.
      if (_statusFlag(bootstrapStatus, 'bypassInstalled')) {
        _emitProgress(
          onProgress: onProgress,
          step: SetupStep.installingNode,
          progress: 0.02,
          message: 'Bionic Bypass already configured',
          detail: 'Reusing existing proot compatibility patches.',
          notificationText: 'Preparing Node.js setup... 45.7%',
        );
      } else {
        await NativeBridge.installBionicBypass();
      }

      final nodeReady = _statusFlag(bootstrapStatus, 'nodeInstalled') &&
          await _isInstalledNodeUsable();

      // Step 3: Install Node.js (45-80%)
      if (nodeReady) {
        _emitProgress(
          onProgress: onProgress,
          step: SetupStep.installingNode,
          progress: 1.0,
          message: 'Node.js already installed',
          detail: 'Reusing existing Node.js runtime and base packages.',
          notificationText: 'Node.js installed 80.0%',
        );
      } else {
        // Fix permissions inside proot (Java extraction may miss execute bits)
        _emitProgress(
          onProgress: onProgress,
          step: SetupStep.installingNode,
          progress: 0.02,
          message: 'Fixing rootfs permissions...',
          notificationText: 'Fixing rootfs permissions... 45.7%',
        );
        // Blanket recursive chmod on all bin/lib directories.
        // Java tar extraction loses execute bits; dpkg needs tar, xz,
        // gzip, rm, mv, etc. — easier to fix everything than enumerate.
        await NativeBridge.runInProot(
          'chmod -R 755 /usr/bin /usr/sbin /bin /sbin '
          '/usr/local/bin /usr/local/sbin 2>/dev/null; '
          'chmod -R +x /usr/lib/apt/ /usr/lib/dpkg/ /usr/libexec/ '
          '/var/lib/dpkg/info/ /usr/share/debconf/ 2>/dev/null; '
          'chmod 755 /lib/*/ld-linux-*.so* /usr/lib/*/ld-linux-*.so* 2>/dev/null; '
          'mkdir -p /var/lib/dpkg/updates /var/lib/dpkg/triggers; '
          'echo permissions_fixed',
        );
        _emitProgress(
          onProgress: onProgress,
          step: SetupStep.installingNode,
          progress: 0.08,
          message: 'Fixing rootfs permissions...',
          notificationText: 'Fixing rootfs permissions... 47.8%',
        );

        await _configureUbuntuMirror(arch);

        // --- Install base packages via apt-get (like Termux proot-distro) ---
        // Now that our proot matches Termux exactly (env -i, clean host env,
        // proper flags), dpkg works normally. No need for Java-side deb
        // extraction — let dpkg+tar handle it inside proot like Termux does.
        await _runEstimatedProgress(
          onProgress: onProgress,
          step: SetupStep.installingNode,
          startProgress: 0.10,
          targetProgress: 0.18,
          message: 'Updating package lists...',
          detail: 'Running apt-get update...',
          estimatedDuration: const Duration(seconds: 25),
          task: () => NativeBridge.runInProot('apt-get update -y'),
        );

        _emitProgress(
          onProgress: onProgress,
          step: SetupStep.installingNode,
          progress: 0.20,
          message: 'Installing base packages...',
          notificationText: 'Installing base packages... 52.0%',
        );
        // ca-certificates: HTTPS for npm/git
        // git: openclaw has git deps (@whiskeysockets/libsignal-node)
        // python3, make, g++: node-gyp needs these to compile native addons
        //   (npm's bundled node-gyp runs as a JS module, not a spawned process,
        //    so proot-compat.js spawn mock can't intercept it)
        // dpkg extracts via tar inside proot — permissions are correct.
        // Post-install scripts (update-ca-certificates) run automatically.
        // Pre-configure tzdata to avoid interactive continent/timezone prompt
        // (tzdata is a dependency of python3 and ignores DEBIAN_FRONTEND on
        // first install if no timezone is pre-set).
        await NativeBridge.runInProot(
          'ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime && '
          'echo "Etc/UTC" > /etc/timezone',
        );
        await _runEstimatedProgress(
          onProgress: onProgress,
          step: SetupStep.installingNode,
          startProgress: 0.22,
          targetProgress: 0.42,
          message: 'Installing base packages...',
          detail: 'Running apt-get install for base packages...',
          estimatedDuration: const Duration(minutes: 3),
          task: () => NativeBridge.runInProot(
            'apt-get install -y --no-install-recommends '
            'ca-certificates git python3 make g++ curl wget',
          ),
        );

        // Git config (.gitconfig) is written by installBionicBypass() on the
        // Java side — directly to $rootfsDir/root/.gitconfig — rewrites
        // SSH→HTTPS for npm git deps (no SSH keys in proot).

        // --- Install Node.js via binary tarball ---
        // Download directly from nodejs.org (bypasses curl/gpg/NodeSource
        // which fail inside proot). Includes node + npm + corepack.
        final nodeTarUrl = AppConstants.getNodeTarballUrl(arch);
        final nodeTarPath = '$filesDir/tmp/nodejs.tar.xz';
        final nodeAssetPath =
            AppConstants.bundledBootstrapAssetPathForUrl(nodeTarUrl);

        final nodeSource = await _prepareBundledOrCachedArchive(
          assetPath: nodeAssetPath,
          destinationPath: nodeTarPath,
        );
        final nodeFromLocal = nodeSource != _PreparedArchiveSource.none;
        if (nodeSource == _PreparedArchiveSource.bundled) {
          _emitProgress(
            onProgress: onProgress,
            step: SetupStep.installingNode,
            progress: 0.80,
            message:
                'Using bundled Node.js ${AppConstants.nodeVersion} package...',
            detail: 'Using packaged Node.js archive.',
            notificationText: 'Using bundled Node.js package... 73.0%',
          );
        } else if (nodeSource == _PreparedArchiveSource.cached) {
          _emitProgress(
            onProgress: onProgress,
            step: SetupStep.installingNode,
            progress: 0.80,
            message:
                'Using cached Node.js ${AppConstants.nodeVersion} package...',
            detail: 'Reusing local Node.js archive cache.',
            notificationText: 'Using cached Node.js package... 73.0%',
          );
        } else {
          await _downloadStepArchive(
            url: nodeTarUrl,
            destinationPath: nodeTarPath,
            onProgress: onProgress,
            step: SetupStep.installingNode,
            startProgress: 0.45,
            endProgress: 0.80,
            idleMessage: 'Downloading Node.js ${AppConstants.nodeVersion}...',
            detailBuilder: (currentMb, totalMb, details) =>
                '$currentMb MB / $totalMb MB | $details',
          );
        }

        try {
          await _runEstimatedProgress(
            onProgress: onProgress,
            step: SetupStep.installingNode,
            startProgress: 0.82,
            targetProgress: 0.92,
            message: 'Extracting Node.js...',
            detail: 'Preparing Node.js files...',
            estimatedDuration: const Duration(seconds: 25),
            task: () => NativeBridge.extractNodeTarball(nodeTarPath),
          );
        } catch (error) {
          if (!nodeFromLocal) {
            rethrow;
          }
          try {
            File(nodeTarPath).deleteSync();
          } catch (_) {}
          await _downloadStepArchive(
            url: nodeTarUrl,
            destinationPath: nodeTarPath,
            onProgress: onProgress,
            step: SetupStep.installingNode,
            startProgress: 0.45,
            endProgress: 0.80,
            idleMessage: 'Local Node.js cache failed, downloading online...',
            detailBuilder: (currentMb, totalMb, details) =>
                '$currentMb MB / $totalMb MB | $details',
          );
          await _runEstimatedProgress(
            onProgress: onProgress,
            step: SetupStep.installingNode,
            startProgress: 0.82,
            targetProgress: 0.92,
            message: 'Extracting Node.js...',
            detail: 'Preparing Node.js files...',
            estimatedDuration: const Duration(seconds: 25),
            task: () => NativeBridge.extractNodeTarball(nodeTarPath),
          );
        }

        _emitProgress(
          onProgress: onProgress,
          step: SetupStep.installingNode,
          progress: 0.96,
          message: 'Verifying Node.js...',
          notificationText: 'Verifying Node.js... 78.6%',
        );
        // node-wrapper.js patches broken proot syscalls before loading npm.
        // /usr/local/bin is on PATH, so node finds the tarball's npm.
        const wrapper = '/root/.openclaw/node-wrapper.js';
        const nodeRun = 'node $wrapper';
        // npm from nodejs.org tarball is at /usr/local/lib/node_modules/npm
        const npmCli = '/usr/local/lib/node_modules/npm/bin/npm-cli.js';
        await NativeBridge.runInProot(
          'node --version && $nodeRun $npmCli --version',
        );
        _emitProgress(
          onProgress: onProgress,
          step: SetupStep.installingNode,
          progress: 1.0,
          message: 'Node.js installed',
          notificationText: 'Node.js installed 80.0%',
        );
      }

      // Step 4: Install OpenClaw (80-98%)
      final installedOpenClawVersion =
          await _openClawVersionService.readInstalledVersion();
      final targetVersion = selectedOpenClawRelease?.version.trim();
      final openClawReady = _statusFlag(bootstrapStatus, 'openclawInstalled') &&
          installedOpenClawVersion != null &&
          (targetVersion == null ||
              targetVersion.isEmpty ||
              OpenClawVersionService.isSameVersion(
                installedVersion: installedOpenClawVersion,
                targetVersion: targetVersion,
              )) &&
          await _isInstalledOpenClawUsable();

      if (openClawReady) {
        _emitProgress(
          onProgress: onProgress,
          step: SetupStep.installingOpenClaw,
          progress: 1.0,
          message: 'OpenClaw already installed',
          detail: 'Reusing OpenClaw $installedOpenClawVersion.',
        );
      } else {
        await _openClawVersionService.installVersion(
          selectedOpenClawRelease?.version ?? 'latest',
          releaseInfo: selectedOpenClawRelease,
          installOptions: installOptions,
          captureLiveLogs: false,
          onProgress: (installProgress) {
            final detail = installProgress.detail?.trim();
            _emitProgress(
              onProgress: onProgress,
              step: SetupStep.installingOpenClaw,
              progress: installProgress.progress,
              message: installProgress.message,
              detail: detail?.isEmpty == true ? null : detail,
              preserveDetail: detail == null || detail.isEmpty,
            );
          },
        );
      }

      // Step 5: Bionic Bypass already installed (before node verification)
      _emitProgress(
        onProgress: onProgress,
        step: SetupStep.configuringBypass,
        progress: 1.0,
        message: 'Bionic Bypass configured',
        notificationText: 'Setup complete! 100.0%',
      );

      // Done
      _stopSetupService();
      _emitProgress(
        onProgress: onProgress,
        step: SetupStep.complete,
        progress: 1.0,
        message: 'Setup complete! Ready to start the gateway.',
        notificationText: 'Setup complete! 100.0%',
      );
    } on DioException catch (e) {
      _stopSetupService();
      onProgress(SetupState(
        step: SetupStep.error,
        error: 'Download failed: ${e.message}. Check your internet connection.',
      ));
    } catch (e) {
      _stopSetupService();
      onProgress(SetupState(
        step: SetupStep.error,
        error: 'Setup failed: $e',
      ));
    } finally {
      await logSubscription.cancel();
    }
  }
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

    if (bytesPerSecond >= 1024 * 1024) {
      return '${(bytesPerSecond / 1024 / 1024).toStringAsFixed(1)} MB/s | ETA ${_formatEta(etaSeconds)}';
    }
    return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s | ETA ${_formatEta(etaSeconds)}';
  }

  String _formatEta(int seconds) {
    final safeSeconds = math.max(0, seconds);
    final minutes = safeSeconds ~/ 60;
    final remainingSeconds = safeSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}

class _MirrorProbeResult {
  final String baseUrl;
  final int elapsedMs;

  const _MirrorProbeResult(this.baseUrl, this.elapsedMs);
}

enum _PreparedArchiveSource {
  none,
  bundled,
  cached,
}
