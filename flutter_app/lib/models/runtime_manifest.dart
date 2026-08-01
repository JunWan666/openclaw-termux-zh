class RuntimeManifestException implements Exception {
  const RuntimeManifestException(this.message);

  final String message;

  @override
  String toString() => 'RuntimeManifestException: $message';
}

class RuntimeManifest {
  const RuntimeManifest({
    required this.schemaVersion,
    required this.runtimeRevision,
    required this.architecture,
    required this.ubuntuVersion,
    required this.nodeVersion,
    required this.openclawVersion,
    required this.archive,
    required this.archiveSha256,
    required this.minimumFreeSpaceBytes,
    required this.createdAt,
  });

  final int schemaVersion;
  final int runtimeRevision;
  final String architecture;
  final String ubuntuVersion;
  final String nodeVersion;
  final String openclawVersion;
  final String archive;
  final String archiveSha256;
  final int minimumFreeSpaceBytes;
  final DateTime createdAt;

  factory RuntimeManifest.fromJson(Map<String, dynamic> json) {
    int requiredInt(String key) {
      final value = json[key];
      if (value is! int) {
        throw RuntimeManifestException('$key must be an integer');
      }
      return value;
    }

    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw RuntimeManifestException('$key must be a non-empty string');
      }
      return value.trim();
    }

    final schemaVersion = requiredInt('schemaVersion');
    if (schemaVersion != 1) {
      throw RuntimeManifestException(
          'unsupported schemaVersion: $schemaVersion');
    }
    final revision = requiredInt('runtimeRevision');
    if (revision < 1) {
      throw const RuntimeManifestException('runtimeRevision must be positive');
    }
    final architecture = requiredString('architecture');
    if (architecture != 'arm64-v8a') {
      throw RuntimeManifestException('unsupported architecture: $architecture');
    }
    final archive = requiredString('archive');
    if (archive.contains('/') ||
        archive.contains('\\') ||
        archive.contains('..')) {
      throw const RuntimeManifestException('archive must be a plain file name');
    }
    final sha256 = requiredString('archiveSha256').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw const RuntimeManifestException(
          'archiveSha256 must be 64 hex characters');
    }
    final minimumFreeSpaceBytes = requiredInt('minimumFreeSpaceBytes');
    if (minimumFreeSpaceBytes <= 0) {
      throw const RuntimeManifestException(
          'minimumFreeSpaceBytes must be positive');
    }
    final createdAtText = requiredString('createdAt');
    final createdAt = DateTime.tryParse(createdAtText);
    if (createdAt == null) {
      throw const RuntimeManifestException('createdAt must be ISO-8601');
    }

    return RuntimeManifest(
      schemaVersion: schemaVersion,
      runtimeRevision: revision,
      architecture: architecture,
      ubuntuVersion: requiredString('ubuntuVersion'),
      nodeVersion: requiredString('nodeVersion'),
      openclawVersion: requiredString('openclawVersion'),
      archive: archive,
      archiveSha256: sha256,
      minimumFreeSpaceBytes: minimumFreeSpaceBytes,
      createdAt: createdAt.toUtc(),
    );
  }
}
