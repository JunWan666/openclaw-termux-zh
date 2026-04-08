import 'dart:convert';
import 'dart:io';

import 'native_bridge.dart';
import 'snapshot_service.dart';

enum BackupImportKind {
  config,
  legacySnapshot,
  workspace,
}

class WorkspaceBackupMetadata {
  const WorkspaceBackupMetadata({
    required this.appVersion,
    required this.openClawVersion,
    required this.createdAt,
    required this.entries,
  });

  final String? appVersion;
  final String? openClawVersion;
  final String? createdAt;
  final List<String> entries;

  factory WorkspaceBackupMetadata.fromMap(Map<String, dynamic> value) {
    return WorkspaceBackupMetadata(
      appVersion: _normalizeVersion(value['appVersion']),
      openClawVersion: _normalizeVersion(value['openClawVersion']),
      createdAt: value['createdAt'] as String?,
      entries: (value['entries'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  static String? _normalizeVersion(Object? value) {
    if (value is! String) {
      return null;
    }

    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
}

class BackupImportBundle {
  const BackupImportBundle._({
    required this.fileName,
    required this.kind,
    this.config,
    this.snapshot,
    this.workspacePath,
    this.workspaceMetadata,
  });

  final String fileName;
  final BackupImportKind kind;
  final Map<String, dynamic>? config;
  final Map<String, dynamic>? snapshot;
  final String? workspacePath;
  final WorkspaceBackupMetadata? workspaceMetadata;

  factory BackupImportBundle.config({
    required String fileName,
    required Map<String, dynamic> config,
  }) {
    return BackupImportBundle._(
      fileName: fileName,
      kind: BackupImportKind.config,
      config: config,
    );
  }

  factory BackupImportBundle.legacySnapshot({
    required String fileName,
    required Map<String, dynamic> snapshot,
  }) {
    return BackupImportBundle._(
      fileName: fileName,
      kind: BackupImportKind.legacySnapshot,
      snapshot: snapshot,
    );
  }

  factory BackupImportBundle.workspace({
    required String fileName,
    required String workspacePath,
    required WorkspaceBackupMetadata metadata,
  }) {
    return BackupImportBundle._(
      fileName: fileName,
      kind: BackupImportKind.workspace,
      workspacePath: workspacePath,
      workspaceMetadata: metadata,
    );
  }

  SnapshotCompatibility? compatibility({
    required String currentAppVersion,
    String? currentOpenClawVersion,
  }) {
    switch (kind) {
      case BackupImportKind.config:
        return null;
      case BackupImportKind.legacySnapshot:
        final value = snapshot;
        if (value == null) {
          return null;
        }
        return SnapshotService.analyzeCompatibility(
          value,
          currentAppVersion: currentAppVersion,
          currentOpenClawVersion: currentOpenClawVersion,
        );
      case BackupImportKind.workspace:
        final metadata = workspaceMetadata;
        if (metadata == null) {
          return null;
        }
        return SnapshotCompatibility(
          snapshotAppVersion: metadata.appVersion,
          currentAppVersion: currentAppVersion,
          snapshotOpenClawVersion: metadata.openClawVersion,
          currentOpenClawVersion: currentOpenClawVersion,
        );
    }
  }

  Future<void> restore({bool restoreNodeEnabled = true}) async {
    switch (kind) {
      case BackupImportKind.config:
        final value = config;
        if (value == null) {
          throw StateError('Missing config payload');
        }
        await NativeBridge.writeRootfsFile(
          'root/.openclaw/openclaw.json',
          const JsonEncoder.withIndent('  ').convert(value),
        );
        break;
      case BackupImportKind.legacySnapshot:
        final value = snapshot;
        if (value == null) {
          throw StateError('Missing snapshot payload');
        }
        await SnapshotService.restoreSnapshot(
          value,
          restoreNodeEnabled: restoreNodeEnabled,
        );
        break;
      case BackupImportKind.workspace:
        final value = workspacePath;
        if (value == null || value.isEmpty) {
          throw StateError('Missing workspace archive path');
        }
        await NativeBridge.restoreWorkspaceBackup(value);
        break;
    }
  }
}

class BackupService {
  static Future<String> buildConfigBackupContent() async {
    final content = await NativeBridge.readRootfsFile(
      'root/.openclaw/openclaw.json',
    );
    if (content == null || content.trim().isEmpty) {
      throw Exception('openclaw.json not found');
    }
    return content;
  }

  static Future<Map<String, dynamic>?> exportConfigBackup({
    required String suggestedName,
  }) async {
    final content = await buildConfigBackupContent();
    return NativeBridge.saveSnapshotFile(
      suggestedName: suggestedName,
      content: content,
    );
  }

  static Future<Map<String, dynamic>?> exportWorkspaceBackup({
    required String suggestedName,
    required String appVersion,
    String? openClawVersion,
  }) async {
    return NativeBridge.exportWorkspaceBackup(
      suggestedName: suggestedName,
      appVersion: appVersion,
      openClawVersion: openClawVersion,
    );
  }

  static Future<BackupImportBundle?> pickBackupForRestore({
    required String emptyFileMessage,
    required String unsupportedFileMessage,
    required String invalidWorkspaceBackupMessage,
  }) async {
    final picked = await NativeBridge.pickBackupFile();
    if (picked == null) {
      return null;
    }

    final fileName = ((picked['name'] as String?)?.trim().isNotEmpty ?? false)
        ? (picked['name'] as String).trim()
        : 'backup';
    final path = picked['path'] as String?;
    if (path == null || path.trim().isEmpty) {
      throw Exception(unsupportedFileMessage);
    }

    final workspaceMetadata = await NativeBridge.inspectWorkspaceBackup(path);
    if (workspaceMetadata != null) {
      return BackupImportBundle.workspace(
        fileName: fileName,
        workspacePath: path,
        metadata: WorkspaceBackupMetadata.fromMap(workspaceMetadata),
      );
    }

    if (fileName.toLowerCase().endsWith('.zip')) {
      throw Exception(invalidWorkspaceBackupMessage);
    }

    late final String content;
    try {
      content = await File(path).readAsString();
    } catch (_) {
      throw Exception(unsupportedFileMessage);
    }

    if (content.trim().isEmpty) {
      throw Exception(emptyFileMessage);
    }

    late final Object decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      throw Exception(unsupportedFileMessage);
    }

    if (decoded is! Map) {
      throw Exception(unsupportedFileMessage);
    }

    final value = Map<String, dynamic>.from(decoded);
    if (_looksLikeLegacySnapshot(value)) {
      return BackupImportBundle.legacySnapshot(
        fileName: fileName,
        snapshot: value,
      );
    }

    return BackupImportBundle.config(
      fileName: fileName,
      config: value,
    );
  }

  static bool _looksLikeLegacySnapshot(Map<String, dynamic> value) {
    return value.containsKey('snapshotSchemaVersion') ||
        value.containsKey('openclawConfig') ||
        value.containsKey('dashboardUrl') ||
        value.containsKey('autoStart') ||
        value.containsKey('nodeEnabled') ||
        value.containsKey('persistentGatewayLogs');
  }
}
