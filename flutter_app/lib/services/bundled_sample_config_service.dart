import 'dart:convert';

import 'package:flutter/services.dart';

import 'native_bridge.dart';

class BundledSampleConfig {
  const BundledSampleConfig({
    required this.version,
    required this.assetPath,
    required this.config,
  });

  final String version;
  final String assetPath;
  final Map<String, dynamic> config;
}

class BundledSampleConfigService {
  static const _assetDirectory = 'assets/sample_configs/openclaw';
  static const _targetConfigPath = 'root/.openclaw/openclaw.json';

  static String assetPathForVersion(String version) =>
      '$_assetDirectory/${version.trim()}.json';

  static Future<BundledSampleConfig?> loadForVersion(String? version) async {
    final normalizedVersion = version?.trim() ?? '';
    if (normalizedVersion.isEmpty) {
      return null;
    }

    final assetPath = assetPathForVersion(normalizedVersion);
    try {
      final content = await rootBundle.loadString(assetPath);
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        return null;
      }

      return BundledSampleConfig(
        version: normalizedVersion,
        assetPath: assetPath,
        config: Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> apply(BundledSampleConfig sample) async {
    await NativeBridge.writeRootfsFile(
      _targetConfigPath,
      const JsonEncoder.withIndent('  ').convert(sample.config),
    );
  }
}
