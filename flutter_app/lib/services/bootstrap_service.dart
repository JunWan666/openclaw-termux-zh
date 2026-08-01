import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:dio/dio.dart';
import '../constants.dart';
import '../l10n/app_localizations.dart';
import '../models/openclaw_install_options.dart';
import '../models/runtime_manifest.dart';
import '../models/setup_state.dart';
import 'install_status_message_formatter.dart';
import 'bundled_runtime_service.dart';
import 'native_bridge.dart';
import 'openclaw_version_service.dart';
import 'provider_config_service.dart';
import 'runtime_compatibility_service.dart';

class BootstrapService {
  final Dio _dio = Dio();
  final OpenClawVersionService _openClawVersionService =
      OpenClawVersionService();
  final BundledRuntimeService _bundledRuntimeService = BundledRuntimeService();
  final RuntimeCompatibilityService _runtimeCompatibilityService =
      const RuntimeCompatibilityService();
  SetupState _lastSetupState = const SetupState();
  CancelToken? _downloadCancelToken;
  bool _cancelRequested = false;

  Future<void> cancelSetup() async {
    _cancelRequested = true;
    _downloadCancelToken?.cancel('Setup cancelled by user');
    try {
      await NativeBridge.cancelSetup();
    } catch (_) {}
    _stopSetupService();
  }

  void _checkCancelled() {
    if (_cancelRequested) {
      throw const _SetupCancelledException();
    }
  }

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

  Future<void> _verifyGatewayHealth() async {
    // The bundled first-run flow verifies Gateway before the initialization
    // screen reaches its final configuration step. Ensure the minimum config
    // (including gateway.mode and the default provider) exists first.
    await ProviderConfigService.ensureInitialAppConfig();
    await ProviderConfigService.ensureGatewayDefaults();
    Object? firstError;
    for (var attempt = 1; attempt <= 2; attempt++) {
      await NativeBridge.startGateway();
      final error = await _waitForGatewayHealth(
        // A first launch from a freshly deployed bundled runtime can spend
        // well over a minute warming Node/OpenClaw under PRoot on real ARM64
        // devices. Keep the process alive long enough to become responsive.
        timeout: const Duration(minutes: 3),
      );
      if (error == null) return;
      firstError ??= error;
      if (attempt < 2) {
        try {
          await NativeBridge.stopGateway();
        } catch (_) {}
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    throw StateError(
      'Gateway health check failed after restart: $firstError',
    );
  }

  Future<Object?> _waitForGatewayHealth({required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      _checkCancelled();
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 2);
        try {
          final request = await client.getUrl(
            Uri.parse('http://127.0.0.1:${AppConstants.gatewayPort}/'),
          );
          final response = await request.close().timeout(
                const Duration(seconds: 3),
              );
          await response.drain<void>();
          if (response.statusCode < 500) return null;
          lastError =
              StateError('Gateway returned HTTP ${response.statusCode}');
        } finally {
          client.close(force: true);
        }
      } catch (error) {
        lastError = error;
      }
      if (!await NativeBridge.isGatewayRunning()) {
        lastError = StateError('Gateway process exited before health check');
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return lastError ?? StateError('Gateway did not become healthy');
  }

  Future<void> _rollbackRootfsInstall() async {
    try {
      await NativeBridge.stopGateway();
    } catch (_) {}
    await NativeBridge.rollbackRootfsInstall();
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

  Future<_PreparedArchiveSource> _prepareLocalArchive({
    required String sourcePath,
    required String destinationPath,
  }) async {
    final source = File(sourcePath);
    if (!source.existsSync() || source.lengthSync() <= 0) {
      return _PreparedArchiveSource.none;
    }

    final destination = File(destinationPath);
    if (source.absolute.path == destination.absolute.path) {
      return _PreparedArchiveSource.localFile;
    }

    if (destination.existsSync()) {
      try {
        destination.deleteSync();
      } catch (_) {}
    }
    destination.parent.createSync(recursive: true);
    await source.copy(destinationPath);
    return destination.existsSync() && destination.lengthSync() > 0
        ? _PreparedArchiveSource.localFile
        : _PreparedArchiveSource.none;
  }

  void _deleteArchiveIfExists(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
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
      cancelToken: _downloadCancelToken,
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

  Future<void> _downloadRootfsArchive({
    required String arch,
    required String destinationPath,
    required void Function(SetupState) onProgress,
    required String idleMessage,
  }) async {
    DioException? lastError;
    final candidates = AppConstants.getRootfsDownloadCandidates(arch);
    for (var index = 0; index < candidates.length; index++) {
      try {
        await _downloadStepArchive(
          url: candidates[index],
          destinationPath: destinationPath,
          onProgress: onProgress,
          step: SetupStep.downloadingRootfs,
          startProgress: 0.0,
          endProgress: 1.0,
          idleMessage: index == 0
              ? idleMessage
              : 'Primary Ubuntu source failed, trying mirror ${index + 1}/${candidates.length}...',
          detailBuilder: (currentMb, totalMb, details) =>
              '$currentMb MB / $totalMb MB | $details',
        );
        return;
      } on DioException catch (error) {
        lastError = error;
        _deleteArchiveIfExists(destinationPath);
        if (_cancelRequested || CancelToken.isCancel(error)) {
          rethrow;
        }
      }
    }
    throw lastError ?? StateError('No Ubuntu rootfs download source available');
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
    return candidates.first;
  }

  Future<void> _configureUbuntuMirror(String arch) async {
    final selectedMirror = await _selectUbuntuMirror(arch);
    await NativeBridge.writeRootfsFile(
      'etc/apt/sources.list',
      AppConstants.buildUbuntuSourcesList(selectedMirror),
    );
  }

  bool _rootfsReady(Map<String, dynamic> status) =>
      _statusFlag(status, 'rootfsExists') &&
      _statusFlag(status, 'binBashExists');

  bool _basePackagesReady(Map<String, dynamic> status) =>
      _statusFlag(status, 'basePackagesInstalled');

  Future<void> _extractRootfsWithProgress({
    required void Function(SetupState) onProgress,
    required String tarPath,
  }) async {
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
        try {
          final filesDir = await NativeBridge.getFilesDir();
          if (await _bundledRuntimeService.isUpgradeRequired(filesDir)) {
            return const SetupState(
              step: SetupStep.checkingStatus,
              progress: 0.0,
              message: 'Bundled runtime update required',
            );
          }
        } catch (_) {
          // A light build or legacy installation may not have a bundled manifest.
        }
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
    bool forceBundledRuntime = false,
  }) async {
    _cancelRequested = false;
    _downloadCancelToken = CancelToken();
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
      await NativeBridge.recoverInterruptedRootfsInstall();
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
      _checkCancelled();
      try {
        await NativeBridge.writeResolv();
      } catch (_) {}

      // Step 1: Download rootfs
      final arch = await NativeBridge.getArch();
      final rootfsUrl = AppConstants.getRootfsUrl(arch);
      final filesDir = await NativeBridge.getFilesDir();
      RuntimeManifest? activeBundledManifest;
      var bundledUpgradeRequired = false;
      try {
        bundledUpgradeRequired =
            await _bundledRuntimeService.isUpgradeRequired(filesDir);
      } catch (_) {}

      // Direct Dart fallback: ensure config dir + resolv.conf exist (#40).
      const resolvContent =
          'nameserver 223.5.5.5\nnameserver 119.29.29.29\nnameserver 8.8.8.8\n';
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
      var bootstrapStatus = await NativeBridge.getBootstrapStatus();
      final rootfsReady = !forceBundledRuntime &&
          !bundledUpgradeRequired &&
          _rootfsReady(bootstrapStatus);
      final tarPath = '$filesDir/tmp/ubuntu-rootfs.tar.gz';
      final rootfsAssetPath =
          AppConstants.bundledBootstrapAssetPathForUrl(rootfsUrl);
      final prebuiltTarPath = '$filesDir/tmp/openclaw-prebuilt-rootfs.tar.gz';
      final prebuiltRootfsAssetPath =
          AppConstants.prebuiltRootfsAssetPathForArch(arch);

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
        var extractedPrebuiltRootfs = false;
        try {
          var prebuiltSource = _PreparedArchiveSource.none;
          final customPrebuiltPath =
              installOptions.normalizedPrebuiltRootfsArchivePath;
          final customPrebuiltUrl = installOptions.normalizedPrebuiltRootfsUrl;

          if (customPrebuiltPath != null) {
            prebuiltSource = await _prepareLocalArchive(
              sourcePath: customPrebuiltPath,
              destinationPath: prebuiltTarPath,
            );
          } else if (customPrebuiltUrl != null) {
            _deleteArchiveIfExists(prebuiltTarPath);
            await _downloadStepArchive(
              url: customPrebuiltUrl,
              destinationPath: prebuiltTarPath,
              onProgress: onProgress,
              step: SetupStep.downloadingRootfs,
              startProgress: 0.0,
              endProgress: 1.0,
              idleMessage: 'Downloading external prebuilt Ubuntu rootfs...',
              detailBuilder: (currentMb, totalMb, details) =>
                  '$currentMb MB / $totalMb MB | $details',
            );
            prebuiltSource = File(prebuiltTarPath).existsSync()
                ? _PreparedArchiveSource.externalUrl
                : _PreparedArchiveSource.none;
          } else {
            try {
              final manifest = await _bundledRuntimeService.loadManifest();
              final expectedArchitecture =
                  RuntimeCompatibilityService.normalizeArchitecture(arch);
              if (manifest.architecture != expectedArchitecture) {
                throw StateError(
                  'Bundled runtime architecture ${manifest.architecture} '
                  'does not match device $expectedArchitecture',
                );
              }
              final compatibility =
                  await NativeBridge.getRuntimeCompatibilityInfo();
              _runtimeCompatibilityService.validate(manifest, compatibility);
              _deleteArchiveIfExists(prebuiltTarPath);
              await NativeBridge.copyBundledAssetToFile(
                assetPath: _bundledRuntimeService.assetPathFor(manifest),
                destinationPath: prebuiltTarPath,
              );
              await _bundledRuntimeService.verifyArchive(
                manifest,
                File(prebuiltTarPath),
              );
              activeBundledManifest = manifest;
              prebuiltSource = _PreparedArchiveSource.bundled;
            } catch (error) {
              if (forceBundledRuntime) rethrow;
              _emitProgress(
                onProgress: onProgress,
                step: SetupStep.downloadingRootfs,
                progress: 0.0,
                message: 'Bundled runtime unavailable, using fallback...',
                detail: error.toString(),
              );
              prebuiltSource = await _prepareBundledOrCachedArchive(
                assetPath: prebuiltRootfsAssetPath,
                destinationPath: prebuiltTarPath,
              );
            }
          }

          if (prebuiltSource != _PreparedArchiveSource.none) {
            switch (prebuiltSource) {
              case _PreparedArchiveSource.bundled:
                _emitProgress(
                  onProgress: onProgress,
                  step: SetupStep.downloadingRootfs,
                  progress: 1.0,
                  message: 'Using bundled prebuilt Ubuntu rootfs package...',
                  detail: 'Using packaged prebuilt Ubuntu rootfs archive.',
                  notificationText:
                      'Using bundled prebuilt Ubuntu rootfs package... 30.0%',
                );
                break;
              case _PreparedArchiveSource.cached:
                _emitProgress(
                  onProgress: onProgress,
                  step: SetupStep.downloadingRootfs,
                  progress: 1.0,
                  message: 'Using cached prebuilt Ubuntu rootfs package...',
                  detail: 'Reusing local prebuilt Ubuntu rootfs archive cache.',
                  notificationText:
                      'Using cached prebuilt Ubuntu rootfs package... 30.0%',
                );
                break;
              case _PreparedArchiveSource.localFile:
                _emitProgress(
                  onProgress: onProgress,
                  step: SetupStep.downloadingRootfs,
                  progress: 1.0,
                  message: 'Using selected prebuilt Ubuntu rootfs package...',
                  detail: 'Using the archive selected from local storage.',
                  notificationText:
                      'Using selected prebuilt Ubuntu rootfs package... 30.0%',
                );
                break;
              case _PreparedArchiveSource.externalUrl:
                _emitProgress(
                  onProgress: onProgress,
                  step: SetupStep.downloadingRootfs,
                  progress: 1.0,
                  message: 'Using downloaded prebuilt Ubuntu rootfs package...',
                  detail: 'Using the archive downloaded from the custom URL.',
                  notificationText:
                      'Using downloaded prebuilt Ubuntu rootfs package... 30.0%',
                );
                break;
              case _PreparedArchiveSource.none:
                break;
            }

            await _extractRootfsWithProgress(
              onProgress: onProgress,
              tarPath: prebuiltTarPath,
            );
            bootstrapStatus = await NativeBridge.getBootstrapStatus();
            if (!_rootfsReady(bootstrapStatus) ||
                !_basePackagesReady(bootstrapStatus)) {
              throw StateError(
                'Prebuilt rootfs is missing required base packages.',
              );
            }
            extractedPrebuiltRootfs = true;
          }
        } catch (error) {
          activeBundledManifest = null;
          if (forceBundledRuntime) rethrow;
          _deleteArchiveIfExists(prebuiltTarPath);
          _emitProgress(
            onProgress: onProgress,
            step: SetupStep.downloadingRootfs,
            progress: 1.0,
            message:
                'Prebuilt rootfs failed, falling back to standard Ubuntu rootfs...',
            detail: error.toString(),
            notificationText:
                'Prebuilt rootfs failed, using standard Ubuntu rootfs... 30.0%',
          );
        }

        if (!extractedPrebuiltRootfs) {
          var rootfsSource = _PreparedArchiveSource.none;
          final customRootfsPath =
              installOptions.normalizedUbuntuRootfsArchivePath;
          final customRootfsUrl = installOptions.normalizedUbuntuRootfsUrl;

          if (customRootfsPath != null) {
            rootfsSource = await _prepareLocalArchive(
              sourcePath: customRootfsPath,
              destinationPath: tarPath,
            );
          } else if (customRootfsUrl != null) {
            _deleteArchiveIfExists(tarPath);
            await _downloadStepArchive(
              url: customRootfsUrl,
              destinationPath: tarPath,
              onProgress: onProgress,
              step: SetupStep.downloadingRootfs,
              startProgress: 0.0,
              endProgress: 1.0,
              idleMessage: 'Downloading selected Ubuntu rootfs...',
              detailBuilder: (currentMb, totalMb, details) =>
                  '$currentMb MB / $totalMb MB | $details',
            );
            rootfsSource = File(tarPath).existsSync()
                ? _PreparedArchiveSource.externalUrl
                : _PreparedArchiveSource.none;
          } else {
            rootfsSource = await _prepareBundledOrCachedArchive(
              assetPath: rootfsAssetPath,
              destinationPath: tarPath,
            );
          }

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
          } else if (rootfsSource == _PreparedArchiveSource.localFile) {
            _emitProgress(
              onProgress: onProgress,
              step: SetupStep.downloadingRootfs,
              progress: 1.0,
              message: 'Using selected Ubuntu rootfs package...',
              detail: 'Using the Ubuntu rootfs archive selected from storage.',
              notificationText: 'Using selected Ubuntu rootfs package... 30.0%',
            );
          } else if (rootfsSource == _PreparedArchiveSource.externalUrl) {
            _emitProgress(
              onProgress: onProgress,
              step: SetupStep.downloadingRootfs,
              progress: 1.0,
              message: 'Using downloaded Ubuntu rootfs package...',
              detail: 'Using the Ubuntu rootfs archive downloaded from URL.',
              notificationText:
                  'Using downloaded Ubuntu rootfs package... 30.0%',
            );
          } else {
            await _downloadRootfsArchive(
              arch: arch,
              destinationPath: tarPath,
              onProgress: onProgress,
              idleMessage: 'Downloading Ubuntu rootfs...',
            );
          }

          try {
            await _extractRootfsWithProgress(
              onProgress: onProgress,
              tarPath: tarPath,
            );
          } catch (error) {
            if (!rootfsFromLocal) {
              rethrow;
            }
            try {
              File(tarPath).deleteSync();
            } catch (_) {}
            await _downloadRootfsArchive(
              arch: arch,
              destinationPath: tarPath,
              onProgress: onProgress,
              idleMessage: 'Local rootfs cache failed, downloading online...',
            );
            await _extractRootfsWithProgress(
              onProgress: onProgress,
              tarPath: tarPath,
            );
          }
        }
        bootstrapStatus = await NativeBridge.getBootstrapStatus();
        _emitProgress(
          onProgress: onProgress,
          step: SetupStep.extractingRootfs,
          progress: 1.0,
          message: 'Rootfs extracted',
          notificationText: 'Rootfs extracted 45.0%',
        );
      }
      bootstrapStatus = await NativeBridge.getBootstrapStatus();

      // Install bionic bypass + cwd-fix + node-wrapper BEFORE using node.
      // The wrapper patches process.cwd() which returns ENOSYS in proot.
      if (_statusFlag(bootstrapStatus, 'bypassInstalled') &&
          activeBundledManifest == null) {
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
        bootstrapStatus = await NativeBridge.getBootstrapStatus();
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
        if (forceBundledRuntime && activeBundledManifest != null) {
          throw StateError(
            'Bundled Node.js failed runtime verification; online repair was not started.',
          );
        }
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

        bootstrapStatus = await NativeBridge.getBootstrapStatus();
        if (_basePackagesReady(bootstrapStatus)) {
          _emitProgress(
            onProgress: onProgress,
            step: SetupStep.installingNode,
            progress: 0.42,
            message: 'Base packages already available',
            detail: 'Skipping apt-get update/install for prebuilt rootfs.',
            notificationText: 'Base packages ready 59.7%',
          );
        } else {
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
          bootstrapStatus = await NativeBridge.getBootstrapStatus();
        }

        // Git config (.gitconfig) is written by installBionicBypass() on the
        // Java side — directly to $rootfsDir/root/.gitconfig — rewrites
        // SSH→HTTPS for npm git deps (no SSH keys in proot).

        // --- Install Node.js via binary tarball ---
        // Download directly from nodejs.org (bypasses curl/gpg/NodeSource
        // which fail inside proot). Includes node + npm + corepack.
        final nodeVersion = AppConstants.getNodeVersionForArch(arch);
        final nodeTarUrl = AppConstants.getNodeTarballUrl(arch);
        final nodeTarPath = '$filesDir/tmp/nodejs.tar.xz';
        final nodeAssetPath =
            AppConstants.bundledBootstrapAssetPathForUrl(nodeTarUrl);

        var nodeSource = _PreparedArchiveSource.none;
        final customNodePath = installOptions.normalizedNodeArchivePath;
        final customNodeUrl = installOptions.normalizedNodeArchiveUrl;
        if (customNodePath != null) {
          nodeSource = await _prepareLocalArchive(
            sourcePath: customNodePath,
            destinationPath: nodeTarPath,
          );
        } else if (customNodeUrl != null) {
          _deleteArchiveIfExists(nodeTarPath);
          await _downloadStepArchive(
            url: customNodeUrl,
            destinationPath: nodeTarPath,
            onProgress: onProgress,
            step: SetupStep.installingNode,
            startProgress: 0.45,
            endProgress: 0.80,
            idleMessage: 'Downloading selected Node.js package...',
            detailBuilder: (currentMb, totalMb, details) =>
                '$currentMb MB / $totalMb MB | $details',
          );
          nodeSource = File(nodeTarPath).existsSync()
              ? _PreparedArchiveSource.externalUrl
              : _PreparedArchiveSource.none;
        } else {
          nodeSource = await _prepareBundledOrCachedArchive(
            assetPath: nodeAssetPath,
            destinationPath: nodeTarPath,
          );
        }
        final nodeFromLocal = nodeSource != _PreparedArchiveSource.none;
        if (nodeSource == _PreparedArchiveSource.bundled) {
          _emitProgress(
            onProgress: onProgress,
            step: SetupStep.installingNode,
            progress: 0.80,
            message: 'Using bundled Node.js $nodeVersion package...',
            detail: 'Using packaged Node.js archive.',
            notificationText: 'Using bundled Node.js package... 73.0%',
          );
        } else if (nodeSource == _PreparedArchiveSource.cached) {
          _emitProgress(
            onProgress: onProgress,
            step: SetupStep.installingNode,
            progress: 0.80,
            message: 'Using cached Node.js $nodeVersion package...',
            detail: 'Reusing local Node.js archive cache.',
            notificationText: 'Using cached Node.js package... 73.0%',
          );
        } else if (nodeSource == _PreparedArchiveSource.localFile) {
          _emitProgress(
            onProgress: onProgress,
            step: SetupStep.installingNode,
            progress: 0.80,
            message: 'Using selected Node.js package...',
            detail: 'Using the Node.js archive selected from storage.',
            notificationText: 'Using selected Node.js package... 73.0%',
          );
        } else if (nodeSource == _PreparedArchiveSource.externalUrl) {
          _emitProgress(
            onProgress: onProgress,
            step: SetupStep.installingNode,
            progress: 0.80,
            message: 'Using downloaded Node.js package...',
            detail: 'Using the Node.js archive downloaded from URL.',
            notificationText: 'Using downloaded Node.js package... 73.0%',
          );
        } else {
          await _downloadStepArchive(
            url: nodeTarUrl,
            destinationPath: nodeTarPath,
            onProgress: onProgress,
            step: SetupStep.installingNode,
            startProgress: 0.45,
            endProgress: 0.80,
            idleMessage: 'Downloading Node.js $nodeVersion...',
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

      bootstrapStatus = await NativeBridge.getBootstrapStatus();

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
        if (forceBundledRuntime && activeBundledManifest != null) {
          throw StateError(
            'Bundled OpenClaw failed runtime verification; online repair was not started.',
          );
        }
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
        progress: 0.5,
        message: 'Performing final runtime checks...',
        notificationText: 'Performing final runtime checks... 99.0%',
      );

      await _verifyGatewayHealth();
      _emitProgress(
        onProgress: onProgress,
        step: SetupStep.configuringBypass,
        progress: 1.0,
        message: 'Local service verified',
        notificationText: 'Setup complete! 100.0%',
      );

      // Done
      if (activeBundledManifest != null) {
        final runtimeDir = Directory('$filesDir/runtime');
        runtimeDir.createSync(recursive: true);
        final compatibility = await NativeBridge.getRuntimeCompatibilityInfo();
        File('${runtimeDir.path}/current.json').writeAsStringSync(
          jsonEncode({
            'schemaVersion': activeBundledManifest.schemaVersion,
            'runtimeRevision': activeBundledManifest.runtimeRevision,
            'architecture': activeBundledManifest.architecture,
            'ubuntuVersion': activeBundledManifest.ubuntuVersion,
            'nodeVersion': activeBundledManifest.nodeVersion,
            'openclawVersion': activeBundledManifest.openclawVersion,
            'archiveSha256': activeBundledManifest.archiveSha256,
            'installedAt': DateTime.now().toUtc().toIso8601String(),
            'pageSizeBytes': compatibility['pageSizeBytes'],
            'androidSdk': compatibility['androidSdk'],
          }),
          flush: true,
        );
      }
      await NativeBridge.commitRootfsInstall();
      _stopSetupService();
      _emitProgress(
        onProgress: onProgress,
        step: SetupStep.complete,
        progress: 1.0,
        message: 'Setup complete! Ready to start the gateway.',
        notificationText: 'Setup complete! 100.0%',
      );
    } on _SetupCancelledException {
      try {
        await _rollbackRootfsInstall();
      } catch (_) {}
      _stopSetupService();
      onProgress(const SetupState(
        step: SetupStep.checkingStatus,
        message: 'Setup stopped',
      ));
    } on DioException catch (e) {
      if (_cancelRequested || CancelToken.isCancel(e)) {
        try {
          await _rollbackRootfsInstall();
        } catch (_) {}
        _stopSetupService();
        onProgress(const SetupState(
          step: SetupStep.checkingStatus,
          message: 'Setup stopped',
        ));
        return;
      }
      _stopSetupService();
      try {
        await _rollbackRootfsInstall();
      } catch (_) {}
      final detail = e.message?.trim();
      final fallback = e.response?.statusCode != null
          ? 'HTTP ${e.response!.statusCode}'
          : e.type.name;
      onProgress(SetupState(
        step: SetupStep.error,
        error:
            'Download failed: ${detail?.isNotEmpty == true ? detail : fallback}. Check your internet connection.',
      ));
    } catch (e) {
      _stopSetupService();
      try {
        await _rollbackRootfsInstall();
      } catch (_) {}
      if (_cancelRequested) {
        onProgress(const SetupState(
          step: SetupStep.checkingStatus,
          message: 'Setup stopped',
        ));
        return;
      }
      onProgress(SetupState(
        step: SetupStep.error,
        error: 'Setup failed: $e',
      ));
    } finally {
      _downloadCancelToken = null;
      await logSubscription.cancel();
    }
  }
}

class _SetupCancelledException implements Exception {
  const _SetupCancelledException();
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
  localFile,
  externalUrl,
}
