import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/models/environment_recovery.dart';
import 'package:openclaw/services/environment_recovery_service.dart';

void main() {
  group('EnvironmentRecoveryClassifier', () {
    test('真正空环境才进入首次安装', () {
      final result = EnvironmentRecoveryClassifier.classify(_snapshot());
      expect(result.state, EnvironmentRecoveryState.fresh);
    });

    test('应用预建 RootFS 运行目录骨架仍属于首次安装', () {
      final result = EnvironmentRecoveryClassifier.classify(_snapshot(
        rootfsExists: true,
      ));
      expect(result.state, EnvironmentRecoveryState.fresh);
    });

    test('命令与兼容层缺失时判定为可自动修复', () {
      final result = EnvironmentRecoveryClassifier.classify(_snapshot(
        rootfsExists: true,
        rootfsPayloadExists: true,
        binBashExists: true,
        nodeExists: true,
        openclawPackageExists: true,
        userDataExists: true,
      ));
      expect(result.state, EnvironmentRecoveryState.repairable);
    });

    test('package.json 缺失但 RootFS 或数据仍在时不得判定为新安装', () {
      final result = EnvironmentRecoveryClassifier.classify(_snapshot(
        rootfsExists: true,
        rootfsPayloadExists: true,
        binBashExists: true,
        nodeExists: true,
        userDataExists: true,
        pendingUpgradeTransactionId: 'upgrade-1',
        npmResidueExists: true,
      ));
      expect(result.state, EnvironmentRecoveryState.upgradeInterrupted);
      expect(result.canAutoRepair, isTrue);
    });

    test('事务刚创建且尚无 npm 残留时仍判定为升级中断', () {
      final result = EnvironmentRecoveryClassifier.classify(_snapshot(
        rootfsExists: true,
        rootfsPayloadExists: true,
        binBashExists: true,
        nodeExists: true,
        userDataExists: true,
        pendingUpgradeTransactionId: 'upgrade-before-npm',
      ));
      expect(result.state, EnvironmentRecoveryState.upgradeInterrupted);
      expect(result.canAutoRepair, isTrue);
    });

    test('首次安装 npm 残留没有升级事务时保留人工恢复入口', () {
      final result = EnvironmentRecoveryClassifier.classify(_snapshot(
        rootfsExists: true,
        rootfsPayloadExists: true,
        binBashExists: true,
        nodeExists: true,
        npmResidueExists: true,
      ));
      expect(result.state, EnvironmentRecoveryState.upgradeInterrupted);
      expect(result.canAutoRepair, isFalse);
    });

    test('用户数据存在但核心环境损坏时要求人工恢复', () {
      final result = EnvironmentRecoveryClassifier.classify(_snapshot(
        rootfsExists: true,
        rootfsPayloadExists: true,
        userDataExists: true,
      ));
      expect(result.state, EnvironmentRecoveryState.manualRecoveryRequired);
      expect(result.state, isNot(EnvironmentRecoveryState.fresh));
    });

    test('完整环境即使 Gateway 正在运行也直接复用', () {
      final result = EnvironmentRecoveryClassifier.classify(_snapshot(
        rootfsExists: true,
        rootfsPayloadExists: true,
        binBashExists: true,
        nodeExists: true,
        openclawPackageExists: true,
        openclawCommandExists: true,
        bypassExists: true,
        nodeWrapperExists: true,
        prootCompatExists: true,
        userDataExists: true,
        gatewayRunning: true,
      ));
      expect(result.state, EnvironmentRecoveryState.complete);
      expect(result.snapshot.gatewayRunning, isTrue);
    });
  });

  test('自动修复只执行幂等重建动作并最终验证版本', () async {
    final actions = _FakeActions();
    final service = EnvironmentRecoveryService(actions: actions);

    final result = await service.repair();

    expect(result.state, EnvironmentRecoveryState.complete);
    expect(actions.calls, [
      'setupDirectories',
      'createOpenClawCommand',
      'installCompatibilityLayer',
      'writeResolv',
      'verifyOpenClaw',
    ]);

    actions.calls.clear();
    final repeated = await service.repair();
    expect(repeated.state, EnvironmentRecoveryState.complete);
    expect(actions.calls, ['verifyOpenClaw']);
  });

  test('升级进程中断后优先回滚待处理事务', () async {
    final actions = _FakeActions(interruptedUpgrade: true);
    final service = EnvironmentRecoveryService(actions: actions);

    final result = await service.repair();

    expect(result.state, EnvironmentRecoveryState.complete);
    expect(actions.calls, ['rollbackUpgrade:upgrade-1', 'verifyOpenClaw']);
  });

  test('事务回滚失败时停留在人工恢复且不执行运行文件重建', () async {
    final actions = _FakeActions(
      interruptedUpgrade: true,
      rollbackFails: true,
    );
    final service = EnvironmentRecoveryService(actions: actions);

    final result = await service.repair();

    expect(result.state, EnvironmentRecoveryState.manualRecoveryRequired);
    expect(result.reason, contains('rollback failed'));
    expect(actions.calls, ['rollbackUpgrade:upgrade-1']);
  });
}

EnvironmentSnapshot _snapshot({
  bool rootfsExists = false,
  bool rootfsPayloadExists = false,
  bool binBashExists = false,
  bool nodeExists = false,
  bool openclawPackageExists = false,
  bool openclawCommandExists = false,
  bool bypassExists = false,
  bool nodeWrapperExists = false,
  bool prootCompatExists = false,
  bool userDataExists = false,
  bool npmResidueExists = false,
  String? pendingUpgradeTransactionId,
  bool gatewayRunning = false,
}) {
  return EnvironmentSnapshot(
    rootfsExists: rootfsExists,
    rootfsPayloadExists: rootfsPayloadExists,
    binBashExists: binBashExists,
    nodeExists: nodeExists,
    openclawPackageExists: openclawPackageExists,
    openclawCommandExists: openclawCommandExists,
    bypassExists: bypassExists,
    nodeWrapperExists: nodeWrapperExists,
    prootCompatExists: prootCompatExists,
    userDataExists: userDataExists,
    npmResidueExists: npmResidueExists,
    pendingUpgradeTransactionId: pendingUpgradeTransactionId,
    gatewayRunning: gatewayRunning,
  );
}

class _FakeActions implements EnvironmentRecoveryActions {
  _FakeActions({
    this.interruptedUpgrade = false,
    this.rollbackFails = false,
  });

  final calls = <String>[];
  final bool interruptedUpgrade;
  final bool rollbackFails;
  var repaired = false;
  var rolledBack = false;

  @override
  Future<void> createOpenClawCommand() async {
    calls.add('createOpenClawCommand');
  }

  @override
  Future<Map<String, dynamic>> getStatus() async => {
        'rootfsExists': true,
        'rootfsPayloadExists': true,
        'binBashExists': true,
        'nodeInstalled': true,
        'openclawPackageExists': !interruptedUpgrade || rolledBack,
        'openclawCommandExists': interruptedUpgrade ? rolledBack : repaired,
        'bypassInstalled': interruptedUpgrade ? rolledBack : repaired,
        'nodeWrapperInstalled': interruptedUpgrade ? rolledBack : repaired,
        'prootCompatInstalled': interruptedUpgrade ? rolledBack : repaired,
        'userDataExists': true,
        'npmResidueExists': interruptedUpgrade && !rolledBack,
        'pendingUpgradeTransactionId':
            interruptedUpgrade && !rolledBack ? 'upgrade-1' : '',
      };

  @override
  Future<void> installCompatibilityLayer() async {
    calls.add('installCompatibilityLayer');
  }

  @override
  Future<bool> isGatewayRunning() async => true;

  @override
  Future<void> setupDirectories() async {
    calls.add('setupDirectories');
  }

  @override
  Future<String> verifyOpenClaw() async {
    calls.add('verifyOpenClaw');
    repaired = true;
    return '2026.7.1-2';
  }

  @override
  Future<void> rollbackUpgrade(String id) async {
    calls.add('rollbackUpgrade:$id');
    if (rollbackFails) throw Exception('rollback failed');
    rolledBack = true;
  }

  @override
  Future<void> writeResolv() async {
    calls.add('writeResolv');
  }
}
