import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

import '../models/runtime_manifest.dart';

class BundledRuntimeService {
  BundledRuntimeService({AssetBundle? assetBundle})
      : _assetBundle = assetBundle ?? rootBundle;

  static const manifestAsset = 'assets/runtime/runtime-manifest.json';
  static const runtimeAssetDirectory = 'assets/runtime';

  final AssetBundle _assetBundle;

  Future<RuntimeManifest> loadManifest() async {
    final raw = await _assetBundle.loadString(manifestAsset);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const RuntimeManifestException('manifest root must be an object');
    }
    return RuntimeManifest.fromJson(decoded);
  }

  String assetPathFor(RuntimeManifest manifest) =>
      '$runtimeAssetDirectory/${manifest.archive}';

  Future<String> sha256OfFile(File file) async {
    final sink = Sha256().newHashSink();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    final hash = await sink.hash();
    return hash.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<void> verifyArchive(RuntimeManifest manifest, File archive) async {
    if (!archive.existsSync() || archive.lengthSync() <= 0) {
      throw const RuntimeManifestException(
          'runtime archive is missing or empty');
    }
    final actual = await sha256OfFile(archive);
    if (actual != manifest.archiveSha256) {
      throw RuntimeManifestException(
        'runtime archive SHA-256 mismatch: expected '
        '${manifest.archiveSha256}, actual $actual',
      );
    }
  }

  Future<bool> isUpgradeRequired(String filesDir) async {
    final current = File('$filesDir/runtime/current.json');
    if (!current.existsSync()) return false;
    final manifest = await loadManifest();
    final decoded = jsonDecode(await current.readAsString());
    if (decoded is! Map<String, dynamic>) return true;
    final installedRevision = decoded['runtimeRevision'];
    final installedArchitecture = decoded['architecture'];
    final installedArchiveSha256 = decoded['archiveSha256'];
    if (installedRevision is! int || installedArchitecture is! String) {
      return true;
    }
    return installedArchitecture != manifest.architecture ||
        installedRevision < manifest.runtimeRevision ||
        installedArchiveSha256 != manifest.archiveSha256;
  }
}
