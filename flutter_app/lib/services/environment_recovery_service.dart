import '../models/environment_recovery.dart';
import 'native_bridge.dart';

abstract class EnvironmentRecoveryActions {
  Future<Map<String, dynamic>> getStatus();
  Future<bool> isGatewayRunning();
  Future<void> setupDirectories();
  Future<void> createOpenClawCommand();
  Future<void> installCompatibilityLayer();
  Future<void> writeResolv();
  Future<String> verifyOpenClaw();
  Future<void> rollbackUpgrade(String id);
}

class NativeEnvironmentRecoveryActions implements EnvironmentRecoveryActions {
  @override
  Future<Map<String, dynamic>> getStatus() => NativeBridge.getBootstrapStatus();

  @override
  Future<bool> isGatewayRunning() => NativeBridge.isGatewayRunning();

  @override
  Future<void> setupDirectories() async {
    await NativeBridge.setupDirs();
  }

  @override
  Future<void> createOpenClawCommand() async {
    await NativeBridge.createBinWrappers('openclaw', force: true);
  }

  @override
  Future<void> installCompatibilityLayer() async {
    await NativeBridge.installBionicBypass();
  }

  @override
  Future<void> writeResolv() async {
    await NativeBridge.writeResolv();
  }

  @override
  Future<String> verifyOpenClaw() =>
      NativeBridge.runInProot('openclaw --version', timeout: 60);

  @override
  Future<void> rollbackUpgrade(String id) async {
    await NativeBridge.rollbackOpenClawUpgrade(id);
  }
}

class EnvironmentRecoveryService {
  EnvironmentRecoveryService({EnvironmentRecoveryActions? actions})
      : _actions = actions ?? NativeEnvironmentRecoveryActions();

  final EnvironmentRecoveryActions _actions;

  Future<EnvironmentAssessment> inspect() => _inspect(verifyCommand: true);

  Future<EnvironmentAssessment> _inspect({required bool verifyCommand}) async {
    final status = await _actions.getStatus();
    var gatewayRunning = false;
    try {
      gatewayRunning = await _actions.isGatewayRunning();
    } catch (_) {}
    final assessment = EnvironmentRecoveryClassifier.classify(
      EnvironmentSnapshot.fromStatus(
        status,
        gatewayRunning: gatewayRunning,
      ),
    );
    if (verifyCommand &&
        assessment.state == EnvironmentRecoveryState.complete) {
      try {
        await _actions.verifyOpenClaw();
      } catch (_) {
        return EnvironmentAssessment(
          state: EnvironmentRecoveryState.repairable,
          snapshot: assessment.snapshot,
          reason: 'OpenClaw 命令验证失败，可尝试重建运行文件',
        );
      }
    }
    return assessment;
  }

  Future<EnvironmentAssessment> repair() async {
    var before = await inspect();
    if (!before.canAutoRepair) return before;

    try {
      final recoveredTransactionIds = <String>{};
      var transactionId = before.snapshot.pendingUpgradeTransactionId;
      while (before.state == EnvironmentRecoveryState.upgradeInterrupted &&
          transactionId != null &&
          recoveredTransactionIds.add(transactionId)) {
        // 升级进程被终止时优先恢复事务快照，不能在半安装包上重建 wrapper。
        await _actions.rollbackUpgrade(transactionId);
        before = await inspect();
        if (before.state == EnvironmentRecoveryState.complete) return before;
        transactionId = before.snapshot.pendingUpgradeTransactionId;
      }
      if (!before.canAutoRepair) return before;
      if (before.state == EnvironmentRecoveryState.upgradeInterrupted) {
        return EnvironmentAssessment(
          state: EnvironmentRecoveryState.manualRecoveryRequired,
          snapshot: before.snapshot,
          reason: '待处理升级事务回滚后环境仍不完整',
        );
      }

      // 顺序固定且幂等：只重建运行文件，绝不删除或覆盖用户数据目录。
      await _actions.setupDirectories();
      await _actions.createOpenClawCommand();
      await _actions.installCompatibilityLayer();
      await _actions.writeResolv();
      await _actions.verifyOpenClaw();

      final after = await _inspect(verifyCommand: false);
      if (after.state == EnvironmentRecoveryState.complete) return after;
      return EnvironmentAssessment(
        state: EnvironmentRecoveryState.manualRecoveryRequired,
        snapshot: after.snapshot,
        reason: '自动修复完成后验证仍未通过',
      );
    } catch (error) {
      // 恢复失败必须停留在人工恢复页，不能让启动路由退回首次安装。
      return EnvironmentAssessment(
        state: EnvironmentRecoveryState.manualRecoveryRequired,
        snapshot: before.snapshot,
        reason: '自动恢复失败：$error',
      );
    }
  }
}
