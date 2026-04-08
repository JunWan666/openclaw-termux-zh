import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/services/backup_service.dart';

void main() {
  group('BackupImportBundle.compatibility', () {
    test('config backups do not carry version compatibility data', () {
      final bundle = BackupImportBundle.config(
        fileName: 'openclaw.json',
        config: const {},
      );

      expect(
        bundle.compatibility(
          currentAppVersion: '1.9.9',
          currentOpenClawVersion: '2026.4.1',
        ),
        isNull,
      );
    });

    test('legacy snapshot backups reuse snapshot compatibility checks', () {
      final bundle = BackupImportBundle.legacySnapshot(
        fileName: 'legacy-snapshot.json',
        snapshot: const {
          'appVersion': '1.9.9',
          'openclawVersion': '2026.4.1',
        },
      );

      final compatibility = bundle.compatibility(
        currentAppVersion: '1.9.9',
        currentOpenClawVersion: '2026.4.1',
      );

      expect(compatibility, isNotNull);
      expect(compatibility!.requiresConfirmation, isFalse);
    });

    test('workspace backups warn when versions differ', () {
      final bundle = BackupImportBundle.workspace(
        fileName: 'workspace.zip',
        workspacePath: '/tmp/workspace.zip',
        metadata: WorkspaceBackupMetadata.fromMap(
          const {
            'appVersion': '1.9.7',
            'openClawVersion': '2026.3.31',
            'entries': ['openclaw.json', 'memory'],
          },
        ),
      );

      final compatibility = bundle.compatibility(
        currentAppVersion: '1.9.9',
        currentOpenClawVersion: '2026.4.1',
      );

      expect(compatibility, isNotNull);
      expect(compatibility!.hasAppVersionMismatch, isTrue);
      expect(compatibility.hasOpenClawVersionMismatch, isTrue);
    });
  });

  group('WorkspaceBackupMetadata.fromMap', () {
    test('normalizes blank versions and preserves listed entries', () {
      final metadata = WorkspaceBackupMetadata.fromMap(
        const {
          'appVersion': '  ',
          'openClawVersion': '',
          'entries': ['agents', 'memory'],
        },
      );

      expect(metadata.appVersion, isNull);
      expect(metadata.openClawVersion, isNull);
      expect(metadata.entries, ['agents', 'memory']);
    });
  });
}
