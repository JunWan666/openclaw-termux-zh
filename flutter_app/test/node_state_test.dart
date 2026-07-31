import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/models/node_state.dart';

void main() {
  test('配对成功时可以清理上一次连接留下的错误', () {
    const failed = NodeState(
      status: NodeStatus.disconnected,
      errorMessage: 'WebSocket disconnected',
    );

    final paired = failed.copyWith(
      status: NodeStatus.paired,
      connectedAt: DateTime(2026, 7, 30),
      clearError: true,
    );

    expect(paired.status, NodeStatus.paired);
    expect(paired.errorMessage, isNull);
    expect(paired.connectedAt, isNotNull);
  });
}
