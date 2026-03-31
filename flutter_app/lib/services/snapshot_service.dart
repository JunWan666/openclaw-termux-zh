import 'dart:convert';

import 'native_bridge.dart';
import 'openclaw_version_service.dart';
import 'preferences_service.dart';

class SnapshotImportBundle {
  const SnapshotImportBundle({
    required this.fileName,
    required this.snapshot,
  });

  final String fileName;
  final Map<String, dynamic> snapshot;
}

class SnapshotCompatibility {
  const SnapshotCompatibility({
    required this.snapshotAppVersion,
    required this.currentAppVersion,
    required this.snapshotOpenClawVersion,
    required this.currentOpenClawVersion,
  });

  final String? snapshotAppVersion;
  final String? currentAppVersion;
  final String? snapshotOpenClawVersion;
  final String? currentOpenClawVersion;

  bool get hasMissingVersionInfo =>
      snapshotAppVersion == null ||
      snapshotOpenClawVersion == null ||
      currentAppVersion == null ||
      currentOpenClawVersion == null;

  bool get hasAppVersionMismatch =>
      _hasComparableVersions(snapshotAppVersion, currentAppVersion) &&
      !OpenClawVersionService.isSameVersion(
        installedVersion: snapshotAppVersion,
        targetVersion: currentAppVersion,
      );

  bool get hasOpenClawVersionMismatch =>
      _hasComparableVersions(
        snapshotOpenClawVersion,
        currentOpenClawVersion,
      ) &&
      !OpenClawVersionService.isSameVersion(
        installedVersion: snapshotOpenClawVersion,
        targetVersion: currentOpenClawVersion,
      );

  bool get requiresConfirmation =>
      hasMissingVersionInfo ||
      hasAppVersionMismatch ||
      hasOpenClawVersionMismatch;

  static bool _hasComparableVersions(String? left, String? right) {
    return left != null &&
        left.trim().isNotEmpty &&
        right != null &&
        right.trim().isNotEmpty;
  }
}

class SnapshotService {
  static Future<Map<String, dynamic>> buildSnapshot({
    required String appVersion,
    String? openClawVersion,
  }) async {
    final prefs = PreferencesService();
    await prefs.init();
    final openclawJson =
        await NativeBridge.readRootfsFile('root/.openclaw/openclaw.json');
    final persistentGatewayLogs =
        await NativeBridge.isGatewayLogPersistenceEnabled();

    return {
      'snapshotSchemaVersion': 2,
      'version': _normalizeVersion(appVersion),
      'appVersion': _normalizeVersion(appVersion),
      'openclawVersion': _normalizeVersion(openClawVersion),
      'timestamp': DateTime.now().toIso8601String(),
      'openclawConfig': openclawJson,
      'dashboardUrl': prefs.dashboardUrl,
      'autoStart': prefs.autoStartGateway,
      'persistentGatewayLogs': persistentGatewayLogs,
      'nodeEnabled': prefs.nodeEnabled,
      'nodeDeviceToken': prefs.nodeDeviceToken,
      'nodeGatewayHost': prefs.nodeGatewayHost,
      'nodeGatewayPort': prefs.nodeGatewayPort,
      'nodeGatewayToken': prefs.nodeGatewayToken,
    };
  }

  static Future<void> restoreSnapshot(
    Map<String, dynamic> snapshot, {
    bool restoreNodeEnabled = true,
  }) async {
    final prefs = PreferencesService();
    await prefs.init();

    final openclawConfig = snapshot['openclawConfig'] as String?;
    if (openclawConfig != null) {
      await NativeBridge.writeRootfsFile(
        'root/.openclaw/openclaw.json',
        openclawConfig,
      );
    }

    if (snapshot['dashboardUrl'] != null) {
      prefs.dashboardUrl = snapshot['dashboardUrl'] as String;
    }
    if (snapshot['autoStart'] != null) {
      prefs.autoStartGateway = snapshot['autoStart'] as bool;
    }
    if (snapshot['persistentGatewayLogs'] != null) {
      await NativeBridge.setGatewayLogPersistenceEnabled(
        snapshot['persistentGatewayLogs'] as bool,
      );
    }
    if (!restoreNodeEnabled) {
      prefs.nodeEnabled = false;
    } else if (snapshot['nodeEnabled'] != null) {
      prefs.nodeEnabled = snapshot['nodeEnabled'] as bool;
    }
    if (snapshot['nodeDeviceToken'] != null) {
      prefs.nodeDeviceToken = snapshot['nodeDeviceToken'] as String;
    }
    if (snapshot['nodeGatewayHost'] != null) {
      prefs.nodeGatewayHost = snapshot['nodeGatewayHost'] as String;
    }
    if (snapshot['nodeGatewayPort'] != null) {
      prefs.nodeGatewayPort = snapshot['nodeGatewayPort'] as int;
    }
    if (snapshot['nodeGatewayToken'] != null) {
      prefs.nodeGatewayToken = snapshot['nodeGatewayToken'] as String;
    }
  }

  static String? snapshotAppVersion(Map<String, dynamic> snapshot) {
    return _normalizeVersion(snapshot['appVersion'] ?? snapshot['version']);
  }

  static String? snapshotOpenClawVersion(Map<String, dynamic> snapshot) {
    return _normalizeVersion(snapshot['openclawVersion']);
  }

  static SnapshotCompatibility analyzeCompatibility(
    Map<String, dynamic> snapshot, {
    required String currentAppVersion,
    String? currentOpenClawVersion,
  }) {
    return SnapshotCompatibility(
      snapshotAppVersion: snapshotAppVersion(snapshot),
      currentAppVersion: _normalizeVersion(currentAppVersion),
      snapshotOpenClawVersion: snapshotOpenClawVersion(snapshot),
      currentOpenClawVersion: _normalizeVersion(currentOpenClawVersion),
    );
  }

  static Future<SnapshotImportBundle?> pickSnapshotForRestore({
    required String emptyFileMessage,
  }) async {
    final picked = await NativeBridge.pickSnapshotFile();
    if (picked == null) {
      return null;
    }

    final pickedName = (picked['name'] as String?) ?? 'snapshot.json';
    final content = picked['content'] as String?;
    if (content == null || content.isEmpty) {
      throw Exception(emptyFileMessage);
    }

    final snapshot = jsonDecode(content) as Map<String, dynamic>;
    return SnapshotImportBundle(
      fileName: pickedName,
      snapshot: snapshot,
    );
  }

  static Future<String?> pickAndRestoreSnapshot({
    required String emptyFileMessage,
    bool restoreNodeEnabled = true,
  }) async {
    final picked = await pickSnapshotForRestore(
      emptyFileMessage: emptyFileMessage,
    );
    if (picked == null) {
      return null;
    }

    await restoreSnapshot(
      picked.snapshot,
      restoreNodeEnabled: restoreNodeEnabled,
    );
    return picked.fileName;
  }

  static String? _normalizeVersion(Object? value) {
    if (value is! String) {
      return null;
    }

    final normalized = value.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}
