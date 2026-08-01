import 'package:flutter/services.dart';
import '../constants.dart';

class NativeBridge {
  static const _channel = MethodChannel(AppConstants.channelName);
  static const _eventChannel = EventChannel(AppConstants.eventChannelName);
  static const _setupLogEventChannel =
      EventChannel(AppConstants.setupLogEventChannelName);

  static Future<String> getProotPath() async {
    return await _channel.invokeMethod('getProotPath');
  }

  static Future<String> getArch() async {
    return await _channel.invokeMethod('getArch');
  }

  static Future<String> getFilesDir() async {
    return await _channel.invokeMethod('getFilesDir');
  }

  static Future<String> getNativeLibDir() async {
    return await _channel.invokeMethod('getNativeLibDir');
  }

  static Future<Map<String, dynamic>> getRuntimeCompatibilityInfo() async {
    final result = await _channel.invokeMethod('getRuntimeCompatibilityInfo');
    return Map<String, dynamic>.from(result as Map);
  }

  static Future<Map<String, dynamic>> getWebViewPackageInfo() async {
    final result = await _channel.invokeMethod('getWebViewPackageInfo');
    return Map<String, dynamic>.from(result);
  }

  static Future<Map<String, dynamic>> getNpmCacheInfo() async {
    final result = await _channel.invokeMethod('getNpmCacheInfo');
    return Map<String, dynamic>.from(result);
  }

  static Future<bool> setNpmCacheLimit(int limitMiB) async {
    return await _channel.invokeMethod(
      'setNpmCacheLimit',
      {'limitMiB': limitMiB},
    );
  }

  static Future<bool> clearNpmCache() async {
    return await _channel.invokeMethod('clearNpmCache');
  }

  static Future<Map<String, dynamic>> trimNpmCache() async {
    final result = await _channel.invokeMethod('trimNpmCache');
    return Map<String, dynamic>.from(result);
  }

  static Future<bool> isBootstrapComplete() async {
    return await _channel.invokeMethod('isBootstrapComplete');
  }

  static Future<Map<String, dynamic>> getBootstrapStatus() async {
    final result = await _channel.invokeMethod('getBootstrapStatus');
    return Map<String, dynamic>.from(result);
  }

  static Future<bool> extractRootfs(String tarPath) async {
    return await _channel.invokeMethod('extractRootfs', {'tarPath': tarPath});
  }

  static Future<bool> commitRootfsInstall() async {
    return await _channel.invokeMethod('commitRootfsInstall');
  }

  static Future<bool> rollbackRootfsInstall() async {
    return await _channel.invokeMethod('rollbackRootfsInstall');
  }

  static Future<bool> recoverInterruptedRootfsInstall() async {
    return await _channel.invokeMethod('recoverInterruptedRootfsInstall');
  }

  static Future<String> runInProot(String command, {int timeout = 900}) async {
    return await _channel
        .invokeMethod('runInProot', {'command': command, 'timeout': timeout});
  }

  static Future<bool> cancelSetup() async {
    return await _channel.invokeMethod('cancelSetup');
  }

  static Future<bool> startGateway() async {
    return await _channel.invokeMethod('startGateway');
  }

  static Future<bool> stopGateway() async {
    return await _channel.invokeMethod('stopGateway');
  }

  static Future<bool> isGatewayRunning() async {
    return await _channel.invokeMethod('isGatewayRunning');
  }

  static Future<bool> isGatewayLogPersistenceEnabled() async {
    return await _channel.invokeMethod('isGatewayLogPersistenceEnabled');
  }

  static Future<bool> setGatewayLogPersistenceEnabled(bool enabled) async {
    return await _channel.invokeMethod(
      'setGatewayLogPersistenceEnabled',
      {'enabled': enabled},
    );
  }

  static Future<bool> setupDirs() async {
    return await _channel.invokeMethod('setupDirs');
  }

  static Future<bool> installBionicBypass() async {
    return await _channel.invokeMethod('installBionicBypass');
  }

  static Future<bool> writeResolv() async {
    return await _channel.invokeMethod('writeResolv');
  }

  static Future<bool> copyBundledAssetToFile({
    required String assetPath,
    required String destinationPath,
  }) async {
    return await _channel.invokeMethod('copyBundledAssetToFile', {
      'assetPath': assetPath,
      'destinationPath': destinationPath,
    });
  }

  static Future<int> restoreBundledOpenClawPackage(String assetPath) async {
    return await _channel.invokeMethod(
      'restoreBundledOpenClawPackage',
      {'assetPath': assetPath},
    );
  }

  static Future<int> extractDebPackages() async {
    return await _channel.invokeMethod('extractDebPackages');
  }

  static Future<bool> extractNodeTarball(String tarPath) async {
    return await _channel
        .invokeMethod('extractNodeTarball', {'tarPath': tarPath});
  }

  static Future<bool> createBinWrappers(
    String packageName, {
    bool force = false,
  }) async {
    return await _channel.invokeMethod('createBinWrappers', {
      'packageName': packageName,
      'force': force,
    });
  }

  static Future<bool> startTerminalService() async {
    return await _channel.invokeMethod('startTerminalService');
  }

  static Future<bool> stopTerminalService() async {
    return await _channel.invokeMethod('stopTerminalService');
  }

  static Future<bool> isTerminalServiceRunning() async {
    return await _channel.invokeMethod('isTerminalServiceRunning');
  }

  static Future<bool> startNodeService() async {
    return await _channel.invokeMethod('startNodeService');
  }

  static Future<bool> stopNodeService() async {
    return await _channel.invokeMethod('stopNodeService');
  }

  static Future<bool> isNodeServiceRunning() async {
    return await _channel.invokeMethod('isNodeServiceRunning');
  }

  static Future<bool> updateNodeNotification(String text) async {
    return await _channel
        .invokeMethod('updateNodeNotification', {'text': text});
  }

  static Future<bool> requestBatteryOptimization() async {
    return await _channel.invokeMethod('requestBatteryOptimization');
  }

  static Future<bool> isBatteryOptimized() async {
    return await _channel.invokeMethod('isBatteryOptimized');
  }

  static Future<bool> startSetupService() async {
    return await _channel.invokeMethod('startSetupService');
  }

  static Future<bool> updateSetupNotification(String text,
      {int progress = -1}) async {
    return await _channel.invokeMethod(
        'updateSetupNotification', {'text': text, 'progress': progress});
  }

  static Future<bool> stopSetupService() async {
    return await _channel.invokeMethod('stopSetupService');
  }

  static Future<bool> showUrlNotification(String url,
      {String title = 'URL Detected'}) async {
    return await _channel
        .invokeMethod('showUrlNotification', {'url': url, 'title': title});
  }

  static Future<Map<String, dynamic>?> pickSnapshotFile() async {
    final result = await _channel.invokeMethod('pickSnapshotFile');
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  static Future<Map<String, dynamic>?> saveSnapshotFile({
    required String suggestedName,
    required String content,
  }) async {
    final result = await _channel.invokeMethod('saveSnapshotFile', {
      'suggestedName': suggestedName,
      'content': content,
    });
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  static Future<Map<String, dynamic>?> pickBackupFile() async {
    final result = await _channel.invokeMethod('pickBackupFile');
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  static Future<Map<String, dynamic>?> pickBootstrapArchiveFile() async {
    final result = await _channel.invokeMethod('pickBootstrapArchiveFile');
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  static Future<Map<String, dynamic>?> exportWorkspaceBackup({
    required String suggestedName,
    required String appVersion,
    String? openClawVersion,
  }) async {
    final result = await _channel.invokeMethod('exportWorkspaceBackup', {
      'suggestedName': suggestedName,
      'appVersion': appVersion,
      'openClawVersion': openClawVersion,
    });
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  static Future<Map<String, dynamic>?> inspectWorkspaceBackup(
    String path,
  ) async {
    final result = await _channel.invokeMethod(
      'inspectWorkspaceBackup',
      {'path': path},
    );
    if (result == null) return null;
    return Map<String, dynamic>.from(result);
  }

  static Future<bool> restoreWorkspaceBackup(String path) async {
    return await _channel.invokeMethod(
      'restoreWorkspaceBackup',
      {'path': path},
    );
  }

  static Future<Map<String, dynamic>> beginOpenClawUpgrade({
    required String sourceVersion,
    required String targetVersion,
  }) async {
    final result = await _channel.invokeMethod('beginOpenClawUpgrade', {
      'sourceVersion': sourceVersion,
      'targetVersion': targetVersion,
    });
    return Map<String, dynamic>.from(result);
  }

  static Future<bool> commitOpenClawUpgrade({
    required String id,
    String? reportJson,
  }) async {
    return await _channel.invokeMethod('commitOpenClawUpgrade', {
      'id': id,
      'reportJson': reportJson,
    });
  }

  static Future<bool> hasCachedOpenClawVersion(String version) async {
    return await _channel.invokeMethod(
      'hasCachedOpenClawVersion',
      {'version': version},
    );
  }

  static Future<int> restoreCachedOpenClawVersion({
    required String id,
    required String version,
  }) async {
    return await _channel.invokeMethod(
      'restoreCachedOpenClawVersion',
      {'id': id, 'version': version},
    );
  }

  static Future<bool> updateOpenClawUpgrade({
    required String id,
    required String phase,
    String? detailsJson,
  }) async {
    return await _channel.invokeMethod('updateOpenClawUpgrade', {
      'id': id,
      'phase': phase,
      'detailsJson': detailsJson,
    });
  }

  static Future<Map<String, dynamic>> validateOpenClawUpgrade(String id) async {
    final result = await _channel.invokeMethod(
      'validateOpenClawUpgrade',
      {'id': id},
    );
    return Map<String, dynamic>.from(result);
  }

  static Future<bool> rollbackOpenClawUpgrade(String id) async {
    return await _channel.invokeMethod(
      'rollbackOpenClawUpgrade',
      {'id': id},
    );
  }

  static Stream<String> get gatewayLogStream {
    return _eventChannel
        .receiveBroadcastStream()
        .map((event) => event.toString());
  }

  static Stream<String> get setupLogStream {
    return _setupLogEventChannel
        .receiveBroadcastStream()
        .map((event) => event.toString());
  }

  static Future<String?> requestScreenCapture(int durationMs) async {
    return await _channel
        .invokeMethod('requestScreenCapture', {'durationMs': durationMs});
  }

  static Future<bool> stopScreenCapture() async {
    return await _channel.invokeMethod('stopScreenCapture');
  }

  static Future<bool> requestStoragePermission() async {
    return await _channel.invokeMethod('requestStoragePermission');
  }

  static Future<bool> hasStoragePermission() async {
    return await _channel.invokeMethod('hasStoragePermission');
  }

  static Future<String> getExternalStoragePath() async {
    return await _channel.invokeMethod('getExternalStoragePath');
  }

  static Future<bool> installApk(String apkPath) async {
    return await _channel.invokeMethod('installApk', {'apkPath': apkPath});
  }

  static Future<String?> readRootfsFile(String path) async {
    return await _channel.invokeMethod('readRootfsFile', {'path': path});
  }

  static Future<bool> writeRootfsFile(String path, String content) async {
    return await _channel
        .invokeMethod('writeRootfsFile', {'path': path, 'content': content});
  }

  // SSH Service
  static Future<bool> startSshd({int port = 8022}) async {
    return await _channel.invokeMethod('startSshd', {'port': port});
  }

  static Future<bool> stopSshd() async {
    return await _channel.invokeMethod('stopSshd');
  }

  static Future<bool> isSshdRunning() async {
    return await _channel.invokeMethod('isSshdRunning');
  }

  static Future<int> getSshdPort() async {
    return await _channel.invokeMethod('getSshdPort');
  }

  static Future<bool> startCpolarService({
    required String binaryPath,
    required String configPath,
    required String logPath,
    int webPort = 9200,
  }) async {
    return await _channel.invokeMethod('startCpolarService', {
      'binaryPath': binaryPath,
      'configPath': configPath,
      'logPath': logPath,
      'webPort': webPort,
    });
  }

  static Future<bool> stopCpolarService() async {
    return await _channel.invokeMethod('stopCpolarService');
  }

  static Future<bool> isCpolarServiceRunning() async {
    return await _channel.invokeMethod('isCpolarServiceRunning');
  }

  static Future<bool> startLocalModelService({
    required String binaryPath,
    required String modelPath,
    required String logPath,
    required int port,
    required String alias,
    required int contextSize,
    required int threads,
    required int threadsBatch,
    required int batchSize,
    required int ubatchSize,
  }) async {
    return await _channel.invokeMethod('startLocalModelService', {
      'binaryPath': binaryPath,
      'modelPath': modelPath,
      'logPath': logPath,
      'port': port,
      'alias': alias,
      'contextSize': contextSize,
      'threads': threads,
      'threadsBatch': threadsBatch,
      'batchSize': batchSize,
      'ubatchSize': ubatchSize,
    });
  }

  static Future<bool> stopLocalModelService() async {
    return await _channel.invokeMethod('stopLocalModelService');
  }

  static Future<bool> isLocalModelServiceRunning() async {
    return await _channel.invokeMethod('isLocalModelServiceRunning');
  }

  static Future<Map<String, dynamic>?> getLocalModelRuntimeStats() async {
    final result = await _channel.invokeMethod('getLocalModelRuntimeStats');
    if (result == null) {
      return null;
    }
    return Map<String, dynamic>.from(result);
  }

  static Future<List<String>> getDeviceIps() async {
    final result = await _channel.invokeMethod('getDeviceIps');
    return List<String>.from(result);
  }

  static Future<bool> bringToForeground() async {
    return await _channel.invokeMethod('bringToForeground');
  }

  static Future<bool> setRootPassword(String password) async {
    return await _channel
        .invokeMethod('setRootPassword', {'password': password});
  }
}
