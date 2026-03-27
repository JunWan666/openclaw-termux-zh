import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../constants.dart';

class UpdateReleaseAsset {
  const UpdateReleaseAsset({
    required this.name,
    required this.downloadUrl,
  });

  final String name;
  final String downloadUrl;

  bool get isApk => name.toLowerCase().endsWith('.apk');

  bool get isUniversalApk => name.toLowerCase().contains('-universal.apk');

  bool matchesAbi(String abi) => name.toLowerCase().contains('-$abi.apk');
}

class UpdateResult {
  final String latest;
  final String url;
  final bool available;
  final List<UpdateReleaseAsset> assets;

  const UpdateResult({
    required this.latest,
    required this.url,
    required this.available,
    required this.assets,
  });

  UpdateReleaseAsset? preferredApkAssetForArch(String arch) {
    final apkAssets = assets.where((asset) => asset.isApk).toList();
    if (apkAssets.isEmpty) {
      return null;
    }

    final preferredAbi = _preferredAbiForArch(arch);
    if (preferredAbi != null) {
      for (final asset in apkAssets) {
        if (asset.matchesAbi(preferredAbi)) {
          return asset;
        }
      }
    }

    for (final asset in apkAssets) {
      if (asset.isUniversalApk) {
        return asset;
      }
    }

    return null;
  }

  static String? _preferredAbiForArch(String arch) {
    switch (arch.trim().toLowerCase()) {
      case 'aarch64':
        return 'arm64-v8a';
      case 'arm':
        return 'armeabi-v7a';
      case 'x86_64':
        return 'x86_64';
      default:
        return null;
    }
  }
}

class UpdateService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 10),
      sendTimeout: const Duration(seconds: 30),
      followRedirects: true,
      responseType: ResponseType.bytes,
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    ),
  );

  static Future<UpdateResult> check() async {
    final response = await http.get(
      Uri.parse(AppConstants.githubApiLatestRelease),
      headers: {'Accept': 'application/vnd.github.v3+json'},
    );

    if (response.statusCode != 200) {
      throw Exception('GitHub API returned ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final tagName = data['tag_name'] as String;
    final htmlUrl = data['html_url'] as String;
    final assets = ((data['assets'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (rawAsset) => UpdateReleaseAsset(
            name: rawAsset['name'] as String? ?? '',
            downloadUrl: rawAsset['browser_download_url'] as String? ?? '',
          ),
        )
        .where(
          (asset) => asset.name.isNotEmpty && asset.downloadUrl.isNotEmpty,
        )
        .toList();

    // Strip leading 'v' if present
    final latest = tagName.startsWith('v') ? tagName.substring(1) : tagName;
    final available = _isNewer(latest, AppConstants.version);

    return UpdateResult(
      latest: latest,
      url: htmlUrl,
      available: available,
      assets: assets,
    );
  }

  static Future<String> downloadAsset(
    UpdateReleaseAsset asset, {
    void Function(int received, int total)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final updateDir = Directory('${tempDir.path}/updates');
    if (!await updateDir.exists()) {
      await updateDir.create(recursive: true);
    }

    final targetFile = File('${updateDir.path}/${asset.name}');
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    final response = await _dio.download(
      asset.downloadUrl,
      targetFile.path,
      onReceiveProgress: onProgress,
      options: Options(
        headers: const {
          'Accept': 'application/octet-stream',
        },
      ),
    );

    final statusCode = response.statusCode ?? 0;
    if (statusCode < 200 || statusCode >= 400 || !await targetFile.exists()) {
      throw Exception('Download failed with status $statusCode');
    }

    return targetFile.path;
  }

  /// Returns true if [remote] is newer than [local] by semver comparison.
  static bool _isNewer(String remote, String local) {
    final r = remote.split('.').map(int.parse).toList();
    final l = local.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv > lv) return true;
      if (rv < lv) return false;
    }
    return false;
  }
}
