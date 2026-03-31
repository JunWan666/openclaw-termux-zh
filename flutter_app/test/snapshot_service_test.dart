import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/services/snapshot_service.dart';

void main() {
  group('SnapshotService.analyzeCompatibility', () {
    test('does not require confirmation when versions match', () {
      final compatibility = SnapshotService.analyzeCompatibility(
        {
          'appVersion': '1.9.6',
          'openclawVersion': '2026.3.24',
        },
        currentAppVersion: '1.9.6',
        currentOpenClawVersion: '2026.3.24',
      );

      expect(compatibility.requiresConfirmation, isFalse);
      expect(compatibility.hasMissingVersionInfo, isFalse);
      expect(compatibility.hasAppVersionMismatch, isFalse);
      expect(compatibility.hasOpenClawVersionMismatch, isFalse);
    });

    test('warns when snapshot openclaw version differs', () {
      final compatibility = SnapshotService.analyzeCompatibility(
        {
          'appVersion': '1.9.6',
          'openclawVersion': '2026.3.24',
        },
        currentAppVersion: '1.9.6',
        currentOpenClawVersion: '2026.3.31',
      );

      expect(compatibility.requiresConfirmation, isTrue);
      expect(compatibility.hasOpenClawVersionMismatch, isTrue);
      expect(compatibility.hasAppVersionMismatch, isFalse);
    });

    test('warns when snapshot app version differs', () {
      final compatibility = SnapshotService.analyzeCompatibility(
        {
          'appVersion': '1.9.5',
          'openclawVersion': '2026.3.24',
        },
        currentAppVersion: '1.9.6',
        currentOpenClawVersion: '2026.3.24',
      );

      expect(compatibility.requiresConfirmation, isTrue);
      expect(compatibility.hasAppVersionMismatch, isTrue);
      expect(compatibility.hasOpenClawVersionMismatch, isFalse);
    });

    test('warns when snapshot metadata is missing', () {
      final compatibility = SnapshotService.analyzeCompatibility(
        const {},
        currentAppVersion: '1.9.6',
        currentOpenClawVersion: '2026.3.24',
      );

      expect(compatibility.requiresConfirmation, isTrue);
      expect(compatibility.hasMissingVersionInfo, isTrue);
    });
  });
}
