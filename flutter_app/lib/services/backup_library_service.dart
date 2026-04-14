import 'dart:io';

import '../constants.dart';
import 'backup_service.dart';
import 'native_bridge.dart';
import 'snapshot_service.dart';

class BackupLibraryEntry {
  const BackupLibraryEntry({
    required this.fileName,
    required this.path,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.bundle,
    required this.compatibility,
  });

  final String fileName;
  final String path;
  final int sizeBytes;
  final DateTime modifiedAt;
  final BackupImportBundle bundle;
  final SnapshotCompatibility? compatibility;
}

class BackupLibraryService {
  static const _libraryRelativePath = 'backup_library';

  static Future<List<BackupLibraryEntry>> listEntries({
    required String currentAppVersion,
    String? currentOpenClawVersion,
  }) async {
    final libraryDir = await _ensureLibraryDir();
    final files = await libraryDir
        .list(followLinks: false)
        .where((entry) => entry is File)
        .cast<File>()
        .toList();

    final entries = <BackupLibraryEntry>[];
    for (final file in files) {
      final fileName =
          file.uri.pathSegments.isEmpty ? 'backup' : file.uri.pathSegments.last;
      final bundle = await _tryLoadBundle(file.path, fileName: fileName);
      if (bundle == null) {
        continue;
      }
      final compatibility = bundle.compatibility(
        currentAppVersion: currentAppVersion,
        currentOpenClawVersion: currentOpenClawVersion,
      );
      entries.add(
        BackupLibraryEntry(
          fileName: fileName,
          path: file.path,
          sizeBytes: await file.length(),
          modifiedAt: await file.lastModified(),
          bundle: bundle,
          compatibility: compatibility,
        ),
      );
    }

    entries.sort((left, right) => right.modifiedAt.compareTo(left.modifiedAt));
    return entries;
  }

  static Future<BackupLibraryEntry?> importBackupFromPicker({
    required String currentAppVersion,
    String? currentOpenClawVersion,
  }) async {
    final picked = await NativeBridge.pickBackupFile();
    if (picked == null) {
      return null;
    }

    final sourcePath = (picked['path'] as String?)?.trim() ?? '';
    if (sourcePath.isEmpty) {
      throw Exception('Backup file path is missing.');
    }
    final originalName =
        ((picked['name'] as String?)?.trim().isNotEmpty ?? false)
            ? (picked['name'] as String).trim()
            : 'backup';
    final targetFile = await _buildUniqueFile(originalName);
    await File(sourcePath).copy(targetFile.path);

    return _buildEntry(
      targetFile,
      currentAppVersion: currentAppVersion,
      currentOpenClawVersion: currentOpenClawVersion,
    );
  }

  static Future<BackupLibraryEntry> saveCurrentConfigSnapshot({
    required String currentAppVersion,
    String? currentOpenClawVersion,
  }) async {
    final content = await BackupService.buildConfigBackupContent();
    final fileName =
        'openclaw-config-local-${_timestampSuffix()}-v${AppConstants.version}.json';
    final targetFile = await _buildUniqueFile(fileName);
    await targetFile.writeAsString(content, flush: true);
    return _buildEntry(
      targetFile,
      currentAppVersion: currentAppVersion,
      currentOpenClawVersion: currentOpenClawVersion,
    );
  }

  static Future<void> deleteEntry(BackupLibraryEntry entry) async {
    final file = File(entry.path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<BackupLibraryEntry> _buildEntry(
    File file, {
    required String currentAppVersion,
    String? currentOpenClawVersion,
  }) async {
    final fileName =
        file.uri.pathSegments.isEmpty ? 'backup' : file.uri.pathSegments.last;
    final bundle = await BackupService.loadBackupFromPath(
      file.path,
      fileName: fileName,
      emptyFileMessage: 'Backup file is empty.',
      unsupportedFileMessage: 'Unsupported backup file.',
      invalidWorkspaceBackupMessage: 'Invalid workspace backup archive.',
    );
    return BackupLibraryEntry(
      fileName: fileName,
      path: file.path,
      sizeBytes: await file.length(),
      modifiedAt: await file.lastModified(),
      bundle: bundle,
      compatibility: bundle.compatibility(
        currentAppVersion: currentAppVersion,
        currentOpenClawVersion: currentOpenClawVersion,
      ),
    );
  }

  static Future<BackupImportBundle?> _tryLoadBundle(
    String path, {
    required String fileName,
  }) async {
    try {
      return await BackupService.loadBackupFromPath(
        path,
        fileName: fileName,
        emptyFileMessage: 'Backup file is empty.',
        unsupportedFileMessage: 'Unsupported backup file.',
        invalidWorkspaceBackupMessage: 'Invalid workspace backup archive.',
      );
    } catch (_) {
      return null;
    }
  }

  static Future<Directory> _ensureLibraryDir() async {
    final filesDir = await NativeBridge.getFilesDir();
    final directory = Directory('$filesDir/$_libraryRelativePath');
    await directory.create(recursive: true);
    return directory;
  }

  static Future<File> _buildUniqueFile(String fileName) async {
    final directory = await _ensureLibraryDir();
    final sanitized = _sanitizeFileName(fileName);
    final dotIndex = sanitized.lastIndexOf('.');
    final baseName =
        dotIndex >= 0 ? sanitized.substring(0, dotIndex) : sanitized;
    final extension = dotIndex >= 0 ? sanitized.substring(dotIndex) : '';
    var candidate = File('${directory.path}/$sanitized');
    var suffix = 1;
    while (await candidate.exists()) {
      candidate = File('${directory.path}/${baseName}_$suffix$extension');
      suffix += 1;
    }
    return candidate;
  }

  static String _sanitizeFileName(String value) {
    final normalized = value.trim().isEmpty ? 'backup' : value.trim();
    final sanitized = normalized
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^\.+'), '')
        .replaceAll(RegExp(r'^\-+|\-+$'), '');
    return sanitized.isEmpty ? 'backup' : sanitized;
  }

  static String _timestampSuffix() {
    final now = DateTime.now();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    return '$year$month$day-$hour$minute$second';
  }
}
