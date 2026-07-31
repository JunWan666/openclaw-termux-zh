enum UpgradeTransactionPhase {
  prepared,
  packageInstalled,
  doctorChecked,
  configMerged,
  verified,
  committed,
  rolledBack,
}

class UpgradeTransactionRecord {
  const UpgradeTransactionRecord({
    required this.id,
    required this.sourceVersion,
    required this.targetVersion,
    required this.backupPath,
    required this.phase,
    this.doctorSummary,
    this.configChanges = const [],
  });

  final String id;
  final String sourceVersion;
  final String targetVersion;
  final String backupPath;
  final UpgradeTransactionPhase phase;
  final String? doctorSummary;
  final List<UpgradeConfigChange> configChanges;
}

class UpgradeConfigChange {
  const UpgradeConfigChange({
    required this.path,
    required this.kind,
    required this.summary,
  });

  final String path;
  final String kind;
  final String summary;
}
