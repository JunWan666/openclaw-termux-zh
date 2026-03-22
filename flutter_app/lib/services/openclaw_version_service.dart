import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

import '../constants.dart';
import 'native_bridge.dart';

class OpenClawReleaseInfo {
  final String version;
  final int? unpackedSizeBytes;
  final String? nodeRequirement;

  const OpenClawReleaseInfo({
    required this.version,
    this.unpackedSizeBytes,
    this.nodeRequirement,
  });

  factory OpenClawReleaseInfo.fromJson(Map<String, dynamic> json) {
    final dist = json['dist'];
    final engines = json['engines'];

    return OpenClawReleaseInfo(
      version: (json['version'] as String?)?.trim() ?? '',
      unpackedSizeBytes:
          dist is Map<String, dynamic> ? dist['unpackedSize'] as int? : null,
      nodeRequirement:
          engines is Map<String, dynamic> ? engines['node'] as String? : null,
    );
  }

  String? get unpackedSizeLabel {
    final size = unpackedSizeBytes;
    if (size == null || size <= 0) {
      return null;
    }
    return OpenClawVersionService.formatBytes(size);
  }
}

class OpenClawVersionService {
  static const _packageJsonPath =
      'usr/local/lib/node_modules/openclaw/package.json';
  static const _latestReleaseEndpoint =
      'https://registry.npmjs.org/openclaw/latest';
  static const _nodePathMarker = '__OPENCLAW_NODE_PATH__';
  static const _nodeWrapper = '/root/.openclaw/node-wrapper.js';
  static const _npmCli = '/usr/local/lib/node_modules/npm/bin/npm-cli.js';
  final Dio _dio = Dio();

  Future<String?> readInstalledVersion() async {
    try {
      final packageJson = await NativeBridge.readRootfsFile(_packageJsonPath);
      if (packageJson == null || packageJson.trim().isEmpty) {
        return null;
      }

      final decoded = jsonDecode(packageJson);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final version = decoded['version'];
      if (version is String && version.trim().isNotEmpty) {
        return version.trim();
      }
    } catch (_) {}

    return null;
  }

  Future<InstalledNodeRuntime> readInstalledNodeRuntime() async {
    try {
      final output = await NativeBridge.runInProot(
        'node_path="\$(command -v node 2>/dev/null || true)"\n'
        'if [ -z "\$node_path" ] && [ -x /usr/local/bin/node ]; then\n'
        '  node_path=/usr/local/bin/node\n'
        'fi\n'
        'if [ -n "\$node_path" ]; then\n'
        "  printf '$_nodePathMarker%s\\n' \"\$node_path\"\n"
        '  "\$node_path" --version\n'
        'fi\n',
        timeout: 15,
      );

      final lines = LineSplitter.split(output)
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.isEmpty) {
        return const InstalledNodeRuntime();
      }

      String? path;
      String? version;
      for (final line in lines) {
        if (line.startsWith(_nodePathMarker)) {
          path = line.replaceFirst(_nodePathMarker, '').trim();
          continue;
        }

        if (line.startsWith('v')) {
          version = line.replaceFirst(RegExp(r'^v'), '');
        }
      }

      return InstalledNodeRuntime(path: path, version: version);
    } catch (_) {
      return const InstalledNodeRuntime();
    }
  }

  Future<String?> readInstalledNodeVersion() async {
    final runtime = await readInstalledNodeRuntime();
    return runtime.version;
  }

  Future<OpenClawReleaseInfo> fetchLatestRelease() async {
    final response = await http.get(
      Uri.parse(_latestReleaseEndpoint),
      headers: const {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw Exception('npm registry returned ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid npm registry response');
    }

    final release = OpenClawReleaseInfo.fromJson(decoded);
    if (release.version.isEmpty) {
      throw Exception('Latest version missing from registry response');
    }
    return release;
  }

  Future<void> updateToLatest({OpenClawReleaseInfo? latestRelease}) async {
    try {
      await NativeBridge.setupDirs();
    } catch (_) {}
    try {
      await NativeBridge.writeResolv();
    } catch (_) {}

    final release = latestRelease ?? await fetchLatestRelease();
    await ensureNodeRequirement(release.nodeRequirement);
    await NativeBridge.runInProot(
      'node $_nodeWrapper $_npmCli install -g openclaw@latest',
      timeout: 1800,
    );
    await NativeBridge.createBinWrappers('openclaw');
  }

  Future<void> ensureNodeRequirement(String? requirement) async {
    final installedRuntime = await readInstalledNodeRuntime();
    if (_nodeSatisfiesRequirement(installedRuntime.version, requirement)) {
      return;
    }

    final minimumVersion = _minimumNodeVersion(requirement);
    final targetVersion = _selectNodeVersionForRequirement(
        minimumVersion ?? AppConstants.nodeVersion);
    await _installNodeRuntime(targetVersion);

    final refreshedRuntime = await readInstalledNodeRuntime();
    if (!_nodeSatisfiesRequirement(refreshedRuntime.version, requirement)) {
      throw Exception(
        'Node.js update incomplete. Required: ${requirement ?? 'unknown'}, '
        'found: ${refreshedRuntime.version ?? 'not detected'}',
      );
    }
  }

  Future<void> _installNodeRuntime(String version) async {
    final arch = await NativeBridge.getArch();
    final filesDir = await NativeBridge.getFilesDir();
    final tarPath = '$filesDir/tmp/nodejs-$version.tar.xz';
    final tarUrl = AppConstants.getNodeTarballUrlForVersion(arch, version);

    final tarFile = File(tarPath);
    if (tarFile.existsSync()) {
      try {
        tarFile.deleteSync();
      } catch (_) {}
    }

    await _dio.download(tarUrl, tarPath);
    await NativeBridge.extractNodeTarball(tarPath);
    await NativeBridge.runInProot(
      'node --version && node $_nodeWrapper $_npmCli --version',
      timeout: 30,
    );
  }

  String _selectNodeVersionForRequirement(String minimumVersion) {
    if (compareVersions(AppConstants.nodeVersion, minimumVersion) >= 0) {
      return AppConstants.nodeVersion;
    }
    return minimumVersion;
  }

  bool _nodeSatisfiesRequirement(
      String? installedVersion, String? requirement) {
    if (installedVersion == null || installedVersion.trim().isEmpty) {
      return false;
    }

    final minimumVersion = _minimumNodeVersion(requirement);
    if (minimumVersion == null) {
      return true;
    }
    return compareVersions(installedVersion, minimumVersion) >= 0;
  }

  String? _minimumNodeVersion(String? requirement) {
    if (requirement == null || requirement.trim().isEmpty) {
      return null;
    }

    final match = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(requirement);
    return match?.group(1);
  }

  static bool isUpdateAvailable({
    required String? installedVersion,
    required String latestVersion,
  }) {
    if (installedVersion == null || installedVersion.trim().isEmpty) {
      return true;
    }

    return compareVersions(latestVersion, installedVersion) > 0;
  }

  static int compareVersions(String left, String right) {
    final leftParts = _versionParts(left);
    final rightParts = _versionParts(right);
    final maxLength = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;

    for (var i = 0; i < maxLength; i++) {
      final leftValue = i < leftParts.length ? leftParts[i] : 0;
      final rightValue = i < rightParts.length ? rightParts[i] : 0;

      if (leftValue > rightValue) {
        return 1;
      }
      if (leftValue < rightValue) {
        return -1;
      }
    }

    return 0;
  }

  static List<int> _versionParts(String version) {
    return RegExp(r'\d+')
        .allMatches(version)
        .map((match) => int.tryParse(match.group(0) ?? '0') ?? 0)
        .toList();
  }

  static String formatBytes(int bytes) {
    final mb = bytes / 1024 / 1024;
    if (mb < 100) {
      return '~${mb.toStringAsFixed(1)} MB';
    }
    return '~${mb.toStringAsFixed(0)} MB';
  }
}

class InstalledNodeRuntime {
  final String? path;
  final String? version;

  const InstalledNodeRuntime({
    this.path,
    this.version,
  });
}
