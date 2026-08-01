import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/models/runtime_manifest.dart';
import 'package:openclaw/services/bundled_runtime_service.dart';

void main() {
  final valid = <String, dynamic>{
    'schemaVersion': 1,
    'runtimeRevision': 1,
    'architecture': 'arm64-v8a',
    'ubuntuVersion': '24.04.3',
    'nodeVersion': '24.18.1',
    'openclawVersion': '2026.3.23',
    'archive': 'openclaw-runtime-2026.3.23-arm64.tar.gz',
    'archiveSha256': 'a' * 64,
    'minimumFreeSpaceBytes': 1073741824,
    'createdAt': '2026-08-01T00:00:00Z',
  };

  test('parses a complete ARM64 runtime manifest', () {
    final manifest = RuntimeManifest.fromJson(valid);
    expect(manifest.runtimeRevision, 1);
    expect(manifest.architecture, 'arm64-v8a');
    expect(manifest.openclawVersion, '2026.3.23');
  });

  test('rejects missing, incompatible and unsafe fields', () {
    expect(
      () => RuntimeManifest.fromJson({...valid}..remove('archiveSha256')),
      throwsA(isA<RuntimeManifestException>()),
    );
    expect(
      () => RuntimeManifest.fromJson({...valid, 'architecture': 'x86_64'}),
      throwsA(isA<RuntimeManifestException>()),
    );
    expect(
      () =>
          RuntimeManifest.fromJson({...valid, 'archive': '../runtime.tar.gz'}),
      throwsA(isA<RuntimeManifestException>()),
    );
  });

  test('loads manifest and verifies archive SHA-256', () async {
    final temp =
        await Directory.systemTemp.createTemp('openclaw-runtime-test-');
    addTearDown(() => temp.delete(recursive: true));
    final archive = File('${temp.path}/runtime.tar.gz');
    await archive.writeAsString('runtime');
    final service = BundledRuntimeService(
      assetBundle: _StringAssetBundle(jsonEncode(valid)),
    );
    final hash = await service.sha256OfFile(archive);
    final manifest =
        RuntimeManifest.fromJson({...valid, 'archiveSha256': hash});
    await service.verifyArchive(manifest, archive);

    await archive.writeAsString('corrupted');
    expect(
      service.verifyArchive(manifest, archive),
      throwsA(isA<RuntimeManifestException>()),
    );
  });

  test('runtime revision decides reuse and bundled upgrade', () async {
    final temp =
        await Directory.systemTemp.createTemp('openclaw-current-test-');
    addTearDown(() => temp.delete(recursive: true));
    final runtimeDir = Directory('${temp.path}/runtime')..createSync();
    final service = BundledRuntimeService(
      assetBundle: _StringAssetBundle(jsonEncode(valid)),
    );

    expect(await service.isUpgradeRequired(temp.path), isFalse);
    File('${runtimeDir.path}/current.json').writeAsStringSync(jsonEncode({
      'runtimeRevision': 1,
      'architecture': 'arm64-v8a',
      'archiveSha256': 'a' * 64,
    }));
    expect(await service.isUpgradeRequired(temp.path), isFalse);
    File('${runtimeDir.path}/current.json').writeAsStringSync(jsonEncode({
      'runtimeRevision': 0,
      'architecture': 'arm64-v8a',
      'archiveSha256': 'a' * 64,
    }));
    expect(await service.isUpgradeRequired(temp.path), isTrue);
  });
}

class _StringAssetBundle extends CachingAssetBundle {
  _StringAssetBundle(this.value);

  final String value;

  @override
  Future<ByteData> load(String key) async {
    final bytes = utf8.encode(value);
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}
