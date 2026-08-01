import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/models/runtime_manifest.dart';
import 'package:openclaw/services/runtime_compatibility_service.dart';

void main() {
  const service = RuntimeCompatibilityService();
  final manifest = RuntimeManifest.fromJson({
    'schemaVersion': 1,
    'runtimeRevision': 1,
    'architecture': 'arm64-v8a',
    'ubuntuVersion': '24.04.3',
    'nodeVersion': '24.18.1',
    'openclawVersion': '2026.3.23',
    'archive': 'runtime.tar.gz',
    'archiveSha256': 'a' * 64,
    'minimumFreeSpaceBytes': 1073741824,
    'createdAt': '2026-08-01T00:00:00Z',
  });

  test('normalizes Linux and Android architecture aliases', () {
    expect(
      RuntimeCompatibilityService.normalizeArchitecture('aarch64'),
      'arm64-v8a',
    );
    expect(
      RuntimeCompatibilityService.normalizeArchitecture('arm64'),
      'arm64-v8a',
    );
    expect(
      RuntimeCompatibilityService.normalizeArchitecture('armv7l'),
      'armeabi-v7a',
    );
    expect(
      RuntimeCompatibilityService.normalizeArchitecture('armhf'),
      'armeabi-v7a',
    );
    expect(
      RuntimeCompatibilityService.normalizeArchitecture('x86_64'),
      'x86_64',
    );
  });

  test('accepts ARM64 devices with 4KB and 16KB page sizes', () {
    for (final pageSize in [4096, 16384]) {
      final result = service.validate(manifest, {
        'supportedAbis': ['arm64-v8a'],
        'availableBytes': 2147483648,
        'pageSizeBytes': pageSize,
        'androidSdk': 36,
      });
      expect(result.pageSizeBytes, pageSize);
      expect(result.is16KbPageDevice, pageSize == 16384);
    }
  });

  test('rejects ABI mismatch', () {
    expect(
      () => service.validate(manifest, {
        'supportedAbis': ['x86_64'],
        'availableBytes': 2147483648,
        'pageSizeBytes': 4096,
      }),
      throwsA(
        isA<RuntimeCompatibilityException>()
            .having((error) => error.code, 'code', 'ABI_MISMATCH'),
      ),
    );
  });

  test('rejects insufficient storage and unknown page size', () {
    expect(
      () => service.validate(manifest, {
        'supportedAbis': ['arm64-v8a'],
        'availableBytes': 100,
        'pageSizeBytes': 4096,
      }),
      throwsA(
        isA<RuntimeCompatibilityException>()
            .having((error) => error.code, 'code', 'INSUFFICIENT_STORAGE'),
      ),
    );
    expect(
      () => service.validate(manifest, {
        'supportedAbis': ['arm64-v8a'],
        'availableBytes': 2147483648,
        'pageSizeBytes': -1,
      }),
      throwsA(
        isA<RuntimeCompatibilityException>()
            .having((error) => error.code, 'code', 'PAGE_SIZE_UNKNOWN'),
      ),
    );
  });
}
