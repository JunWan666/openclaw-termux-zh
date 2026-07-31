import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/services/upgrade_config_guard.dart';

void main() {
  test('doctor lint 返回 ok=false 时执行配置修复', () {
    expect(
      UpgradeConfigGuard.doctorNeedsFix(
        '{"ok":false,"findings":[{"severity":"warning"}]}',
      ),
      isTrue,
    );
    expect(
      UpgradeConfigGuard.doctorNeedsFix(
        '{"ok":true,"findings":[]}',
      ),
      isFalse,
    );
  });

  test('doctor error 或显式可修复 finding 需要修复', () {
    expect(
      UpgradeConfigGuard.doctorNeedsFix(
        '{"ok":true,"findings":[{"severity":"error"}]}',
      ),
      isTrue,
    );
    expect(
      UpgradeConfigGuard.doctorNeedsFix(
        '{"ok":true,"findings":[{"severity":"warning","fixable":true}]}',
      ),
      isTrue,
    );
  });

  test('不可修复 warning、空输出和非 JSON 输出不误触发修复', () {
    expect(
      UpgradeConfigGuard.doctorNeedsFix(
        '{"ok":true,"findings":[{"severity":"warning"}]}',
      ),
      isFalse,
    );
    expect(UpgradeConfigGuard.doctorNeedsFix(''), isFalse);
    expect(UpgradeConfigGuard.doctorNeedsFix('doctor unavailable'), isFalse);
  });
}
