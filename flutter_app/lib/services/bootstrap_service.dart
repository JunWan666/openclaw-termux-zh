import 'dart:io';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import '../constants.dart';
import '../models/setup_state.dart';
import 'native_bridge.dart';
import 'openclaw_version_service.dart';

class BootstrapService {
  final Dio _dio = Dio();
  final OpenClawVersionService _openClawVersionService =
      OpenClawVersionService();

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

  void _emitProgress({
    required void Function(SetupState) onProgress,
    required SetupStep step,
    required double progress,
    required String message,
    String? notificationText,
  }) {
    final clampedProgress = _clampProgress(progress);
    onProgress(SetupState(
      step: step,
      progress: clampedProgress,
      message: message,
    ));
    final overallProgress = _overallProgressFor(step, clampedProgress);
    _updateSetupNotification(
      notificationText ?? '$message ${_formatPercent(overallProgress)}',
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
    Duration tick = const Duration(milliseconds: 800),
  }) async {
    _emitProgress(
      onProgress: onProgress,
      step: step,
      progress: startProgress,
      message: message,
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
  }) async {
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
      final tarPath = '$filesDir/tmp/ubuntu-rootfs.tar.gz';

      _emitProgress(
        onProgress: onProgress,
        step: SetupStep.downloadingRootfs,
        progress: 0.0,
        message: 'Downloading Ubuntu rootfs...',
        notificationText: 'Downloading Ubuntu rootfs... 5.0%',
      );

      await _dio.download(
        rootfsUrl,
        tarPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            final mb = (received / 1024 / 1024).toStringAsFixed(1);
            final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
            final overallProgress = _overallProgressFor(
              SetupStep.downloadingRootfs,
              progress,
            );
            _emitProgress(
              onProgress: onProgress,
              step: SetupStep.downloadingRootfs,
              progress: progress,
              message: 'Downloading: $mb MB / $totalMb MB',
              notificationText:
                  'Downloading rootfs: $mb / $totalMb MB (${_formatPercent(overallProgress)})',
            );
          }
        },
      );

      // Step 2: Extract rootfs (30-45%)
      await _runEstimatedProgress(
        onProgress: onProgress,
        step: SetupStep.extractingRootfs,
        startProgress: 0.02,
        targetProgress: 0.92,
        message: 'Extracting rootfs (this takes a while)...',
        estimatedDuration: const Duration(minutes: 2),
        task: () => NativeBridge.extractRootfs(tarPath),
      );
      _emitProgress(
        onProgress: onProgress,
        step: SetupStep.extractingRootfs,
        progress: 1.0,
        message: 'Rootfs extracted',
        notificationText: 'Rootfs extracted 45.0%',
      );

      // Install bionic bypass + cwd-fix + node-wrapper BEFORE using node.
      // The wrapper patches process.cwd() which returns ENOSYS in proot.
      await NativeBridge.installBionicBypass();

      // Step 3: Install Node.js (45-80%)
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

      _emitProgress(
        onProgress: onProgress,
        step: SetupStep.installingNode,
        progress: 0.45,
        message: 'Downloading Node.js ${AppConstants.nodeVersion}...',
        notificationText: 'Downloading Node.js... 60.8%',
      );
      await _dio.download(
        nodeTarUrl,
        nodeTarPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final downloadRatio = received / total;
            final progress = 0.45 + (downloadRatio * 0.35);
            final mb = (received / 1024 / 1024).toStringAsFixed(1);
            final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
            final overallProgress = _overallProgressFor(
              SetupStep.installingNode,
              progress,
            );
            _emitProgress(
              onProgress: onProgress,
              step: SetupStep.installingNode,
              progress: progress,
              message: 'Downloading Node.js: $mb MB / $totalMb MB',
              notificationText:
                  'Downloading Node.js: $mb / $totalMb MB (${_formatPercent(overallProgress)})',
            );
          }
        },
      );

      await _runEstimatedProgress(
        onProgress: onProgress,
        step: SetupStep.installingNode,
        startProgress: 0.82,
        targetProgress: 0.92,
        message: 'Extracting Node.js...',
        estimatedDuration: const Duration(seconds: 25),
        task: () => NativeBridge.extractNodeTarball(nodeTarPath),
      );

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

      // Step 4: Install OpenClaw (80-98%)
      await _runEstimatedProgress(
        onProgress: onProgress,
        step: SetupStep.installingOpenClaw,
        startProgress: 0.02,
        targetProgress: 0.72,
        message: 'Installing OpenClaw (this may take a few minutes)...',
        estimatedDuration: const Duration(minutes: 4),
        task: () => _openClawVersionService.installVersion(
          selectedOpenClawRelease?.version ?? 'latest',
          releaseInfo: selectedOpenClawRelease,
        ),
      );

      _emitProgress(
        onProgress: onProgress,
        step: SetupStep.installingOpenClaw,
        progress: 0.92,
        message: 'Verifying OpenClaw...',
        notificationText: 'Verifying OpenClaw... 96.6%',
      );
      await NativeBridge.runInProot(
          'openclaw --version || echo openclaw_installed');
      _emitProgress(
        onProgress: onProgress,
        step: SetupStep.installingOpenClaw,
        progress: 1.0,
        message: 'OpenClaw installed',
        notificationText: 'OpenClaw installed 98.0%',
      );

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
    }
  }
}
