import 'dart:convert';

import 'native_bridge.dart';
import 'preferences_service.dart';

class SnapshotService {
  static Future<Map<String, dynamic>> buildSnapshot(String version) async {
    final prefs = PreferencesService();
    await prefs.init();
    final openclawJson =
        await NativeBridge.readRootfsFile('root/.openclaw/openclaw.json');
    final persistentGatewayLogs =
        await NativeBridge.isGatewayLogPersistenceEnabled();

    return {
      'version': version,
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

  static Future<void> restoreSnapshot(Map<String, dynamic> snapshot) async {
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
    if (snapshot['nodeEnabled'] != null) {
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

  static Future<String?> pickAndRestoreSnapshot({
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
    await restoreSnapshot(snapshot);
    return pickedName;
  }
}
