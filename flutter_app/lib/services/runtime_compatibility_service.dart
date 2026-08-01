import '../models/runtime_manifest.dart';

class RuntimeCompatibilityException implements Exception {
  const RuntimeCompatibilityException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'RuntimeCompatibilityException($code): $message';
}

class RuntimeCompatibilityResult {
  const RuntimeCompatibilityResult({
    required this.pageSizeBytes,
    required this.androidSdk,
    required this.availableBytes,
  });

  final int pageSizeBytes;
  final int androidSdk;
  final int availableBytes;

  bool get is16KbPageDevice => pageSizeBytes == 16384;
}

class RuntimeCompatibilityService {
  const RuntimeCompatibilityService();

  static String normalizeArchitecture(String architecture) {
    switch (architecture.trim().toLowerCase()) {
      case 'aarch64':
      case 'arm64':
      case 'arm64-v8a':
        return 'arm64-v8a';
      case 'arm':
      case 'armv7l':
      case 'armhf':
      case 'armeabi-v7a':
        return 'armeabi-v7a';
      default:
        return architecture.trim().toLowerCase();
    }
  }

  RuntimeCompatibilityResult validate(
    RuntimeManifest manifest,
    Map<String, dynamic> device,
  ) {
    final supportedAbis = (device['supportedAbis'] as List?)
            ?.map((value) => value.toString())
            .toList() ??
        const <String>[];
    if (!supportedAbis.contains(manifest.architecture)) {
      throw RuntimeCompatibilityException(
        'ABI_MISMATCH',
        'Device ABI list does not contain ${manifest.architecture}: '
            '${supportedAbis.join(', ')}',
      );
    }

    final availableBytes = (device['availableBytes'] as num?)?.toInt() ?? 0;
    if (availableBytes < manifest.minimumFreeSpaceBytes) {
      throw RuntimeCompatibilityException(
        'INSUFFICIENT_STORAGE',
        'Required ${manifest.minimumFreeSpaceBytes} bytes, '
            'available $availableBytes bytes',
      );
    }

    final pageSizeBytes = (device['pageSizeBytes'] as num?)?.toInt() ?? -1;
    if (pageSizeBytes <= 0) {
      throw const RuntimeCompatibilityException(
        'PAGE_SIZE_UNKNOWN',
        'Unable to determine device memory page size',
      );
    }
    if (pageSizeBytes != 4096 && pageSizeBytes != 16384) {
      throw RuntimeCompatibilityException(
        'PAGE_SIZE_UNSUPPORTED',
        'Unsupported device memory page size: $pageSizeBytes bytes',
      );
    }

    return RuntimeCompatibilityResult(
      pageSizeBytes: pageSizeBytes,
      androidSdk: (device['androidSdk'] as num?)?.toInt() ?? -1,
      availableBytes: availableBytes,
    );
  }
}
