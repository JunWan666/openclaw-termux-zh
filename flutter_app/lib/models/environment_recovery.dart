enum EnvironmentRecoveryState {
  fresh,
  complete,
  repairable,
  upgradeInterrupted,
  manualRecoveryRequired,
}

class EnvironmentSnapshot {
  const EnvironmentSnapshot({
    required this.rootfsExists,
    required this.rootfsPayloadExists,
    required this.binBashExists,
    required this.nodeExists,
    required this.openclawPackageExists,
    required this.openclawCommandExists,
    required this.bypassExists,
    required this.nodeWrapperExists,
    required this.prootCompatExists,
    required this.userDataExists,
    required this.npmResidueExists,
    required this.pendingUpgradeTransactionId,
    required this.gatewayRunning,
  });

  final bool rootfsExists;
  final bool rootfsPayloadExists;
  final bool binBashExists;
  final bool nodeExists;
  final bool openclawPackageExists;
  final bool openclawCommandExists;
  final bool bypassExists;
  final bool nodeWrapperExists;
  final bool prootCompatExists;
  final bool userDataExists;
  final bool npmResidueExists;
  final String? pendingUpgradeTransactionId;
  final bool gatewayRunning;

  factory EnvironmentSnapshot.fromStatus(
    Map<String, dynamic> status, {
    required bool gatewayRunning,
  }) {
    bool flag(String key) => status[key] == true;
    return EnvironmentSnapshot(
      rootfsExists: flag('rootfsExists'),
      rootfsPayloadExists: flag('rootfsPayloadExists'),
      binBashExists: flag('binBashExists'),
      nodeExists: flag('nodeInstalled'),
      openclawPackageExists: flag('openclawPackageExists'),
      openclawCommandExists: flag('openclawCommandExists'),
      bypassExists: flag('bypassInstalled'),
      nodeWrapperExists: flag('nodeWrapperInstalled'),
      prootCompatExists: flag('prootCompatInstalled'),
      userDataExists: flag('userDataExists'),
      npmResidueExists: flag('npmResidueExists'),
      pendingUpgradeTransactionId:
          _nonEmptyString(status['pendingUpgradeTransactionId']),
      gatewayRunning: gatewayRunning,
    );
  }

  bool get runtimeFilesComplete =>
      openclawCommandExists &&
      bypassExists &&
      nodeWrapperExists &&
      prootCompatExists;

  bool get repairPrerequisitesComplete =>
      rootfsExists && binBashExists && nodeExists && openclawPackageExists;
}

class EnvironmentAssessment {
  const EnvironmentAssessment({
    required this.state,
    required this.snapshot,
    this.reason,
  });

  final EnvironmentRecoveryState state;
  final EnvironmentSnapshot snapshot;
  final String? reason;

  bool get shouldEnterDashboard => state == EnvironmentRecoveryState.complete;
  bool get canAutoRepair =>
      state == EnvironmentRecoveryState.repairable ||
      (state == EnvironmentRecoveryState.upgradeInterrupted &&
          snapshot.pendingUpgradeTransactionId != null);
}

String? _nonEmptyString(Object? value) {
  final normalized = value?.toString().trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

class EnvironmentRecoveryClassifier {
  const EnvironmentRecoveryClassifier._();

  static EnvironmentAssessment classify(EnvironmentSnapshot snapshot) {
    if (snapshot.repairPrerequisitesComplete && snapshot.runtimeFilesComplete) {
      return EnvironmentAssessment(
        state: EnvironmentRecoveryState.complete,
        snapshot: snapshot,
      );
    }

    // 仅重建可再生运行文件，不触碰配置、会话和工作区数据。
    if (snapshot.repairPrerequisitesComplete) {
      return EnvironmentAssessment(
        state: EnvironmentRecoveryState.repairable,
        snapshot: snapshot,
        reason: '检测到可重建的命令或兼容层文件缺失',
      );
    }

    // Native initialization creates an empty RootFS runtime skeleton. It remains
    // a fresh install until extraction/runtime artifacts or user data exist.
    if (!snapshot.rootfsPayloadExists &&
        !snapshot.userDataExists &&
        !snapshot.npmResidueExists) {
      return EnvironmentAssessment(
        state: EnvironmentRecoveryState.fresh,
        snapshot: snapshot,
      );
    }

    if (snapshot.pendingUpgradeTransactionId != null ||
        snapshot.npmResidueExists ||
        (snapshot.rootfsPayloadExists &&
            !snapshot.userDataExists &&
            !snapshot.openclawPackageExists)) {
      return EnvironmentAssessment(
        state: EnvironmentRecoveryState.upgradeInterrupted,
        snapshot: snapshot,
        reason: '检测到安装或升级中断残留',
      );
    }

    return EnvironmentAssessment(
      state: EnvironmentRecoveryState.manualRecoveryRequired,
      snapshot: snapshot,
      reason:
          snapshot.userDataExists ? '用户数据仍在，但核心运行环境不完整' : '现有 RootFS 无法安全自动恢复',
    );
  }
}
