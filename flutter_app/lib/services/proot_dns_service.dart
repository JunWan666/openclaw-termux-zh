import 'dart:io';

import 'native_bridge.dart';

class ProotDnsService {
  static const resolvContent =
      'nameserver 223.5.5.5\nnameserver 119.29.29.29\nnameserver 8.8.8.8\n';

  const ProotDnsService._();

  /// Ensure host and rootfs DNS files exist before any PRoot entry point.
  /// Android app updates can leave filesDir partially recreated, which makes
  /// PRoot fail before the actual command starts if config/resolv.conf is gone.
  static Future<void> ensureReady() async {
    try {
      await NativeBridge.setupDirs();
    } catch (_) {}

    try {
      await NativeBridge.writeResolv();
    } catch (_) {}

    try {
      final filesDir = await NativeBridge.getFilesDir();
      _ensureFile('$filesDir/config/resolv.conf');
      _ensureFile('$filesDir/rootfs/ubuntu/etc/resolv.conf');
    } catch (_) {}
  }

  static void _ensureFile(String path) {
    final file = File(path);
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.file && file.lengthSync() > 0) {
      return;
    }
    if (type != FileSystemEntityType.notFound) {
      try {
        file.deleteSync(recursive: true);
      } catch (_) {}
    }
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(resolvContent);
  }
}
