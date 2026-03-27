import 'package:flutter_test/flutter_test.dart';

import 'package:openclaw/services/update_service.dart';

void main() {
  group('UpdateResult.preferredApkAssetForArch', () {
    const assets = [
      UpdateReleaseAsset(
        name: 'OpenClaw-v1.9.0-universal.apk',
        downloadUrl: 'https://example.com/universal.apk',
      ),
      UpdateReleaseAsset(
        name: 'OpenClaw-v1.9.0-arm64-v8a.apk',
        downloadUrl: 'https://example.com/arm64.apk',
      ),
      UpdateReleaseAsset(
        name: 'OpenClaw-v1.9.0-armeabi-v7a.apk',
        downloadUrl: 'https://example.com/arm.apk',
      ),
      UpdateReleaseAsset(
        name: 'OpenClaw-v1.9.0-x86_64.apk',
        downloadUrl: 'https://example.com/x86_64.apk',
      ),
      UpdateReleaseAsset(
        name: 'OpenClaw-v1.9.0.aab',
        downloadUrl: 'https://example.com/app.aab',
      ),
    ];

    const result = UpdateResult(
      latest: '1.9.0',
      url: 'https://example.com/release',
      available: true,
      assets: assets,
    );

    test('prefers exact arm64 asset for aarch64 devices', () {
      expect(
        result.preferredApkAssetForArch('aarch64')?.name,
        'OpenClaw-v1.9.0-arm64-v8a.apk',
      );
    });

    test('prefers exact arm asset for arm devices', () {
      expect(
        result.preferredApkAssetForArch('arm')?.name,
        'OpenClaw-v1.9.0-armeabi-v7a.apk',
      );
    });

    test('falls back to universal apk when architecture is unsupported', () {
      expect(
        result.preferredApkAssetForArch('x86')?.name,
        'OpenClaw-v1.9.0-universal.apk',
      );
    });

    test('returns null when no apk asset exists', () {
      const noApkResult = UpdateResult(
        latest: '1.9.0',
        url: 'https://example.com/release',
        available: true,
        assets: [
          UpdateReleaseAsset(
            name: 'OpenClaw-v1.9.0.aab',
            downloadUrl: 'https://example.com/app.aab',
          ),
        ],
      );

      expect(noApkResult.preferredApkAssetForArch('aarch64'), isNull);
    });
  });
}
