import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/models/gateway_protocol.dart';
import 'package:openclaw/models/node_frame.dart';

void main() {
  group('GatewayHello', () {
    test('解析 v3 hello-ok 并忽略未知字段', () {
      final hello = GatewayHello.fromPayload({
        'protocol': 3,
        'auth': {'deviceToken': 'device-v3'},
        'unknownFutureField': true,
      });

      expect(hello.protocol, 3);
      expect(hello.deviceToken, 'device-v3');
      expect(hello.raw['unknownFutureField'], true);
    });

    test('解析 v4 auth、scope、session、policy 与 feature', () {
      final hello = GatewayHello.fromPayload({
        'protocol': 4,
        'auth': {
          'deviceToken': 'device-v4',
          'role': 'node',
          'scopes': ['node.device', 'node.invoke'],
        },
        'sessionDefaults': {'mainSessionKey': 'agent:main'},
        'policy': {'maxPayload': 1024},
        'features': {'subscriptions': true},
      });

      expect(hello.protocol, 4);
      expect(hello.role, 'node');
      expect(hello.scopes, ['node.device', 'node.invoke']);
      expect(hello.mainSessionKey, 'agent:main');
      expect(hello.policy['maxPayload'], 1024);
      expect(hello.features['subscriptions'], true);
    });

    test('未来字段类型异常时忽略无效值而不导致解析失败', () {
      final hello = GatewayHello.fromPayload({
        'protocol': '4',
        'auth': {
          'role': {'future': true},
          'deviceToken': 42,
          'scopes': ['node.device', 7],
        },
        'sessionDefaults': {'mainSessionKey': false},
      });

      expect(hello.protocol, 4);
      expect(hello.role, isNull);
      expect(hello.deviceToken, isNull);
      expect(hello.scopes, ['node.device']);
      expect(hello.mainSessionKey, isNull);
    });
  });

  group('GatewayErrorInfo', () {
    test('优先读取 v4 details 中的结构化字段', () {
      final error = GatewayErrorInfo.fromMaps({
        'message': 'token rejected',
        'details': {
          'code': 'AUTH_TOKEN_INVALID',
          'reason': 'expired',
          'recommendedNextStep': 'retry-device-token',
          'canRetryWithDeviceToken': true,
          'retryAfterMs': 800,
        },
      }, null);

      expect(error.code, 'AUTH_TOKEN_INVALID');
      expect(error.reason, 'expired');
      expect(error.canRetryWithDeviceToken, true);
      expect(error.retryAfterMs, 800);
    });

    test('兼容 v3 顶层错误', () {
      final error = GatewayErrorInfo.fromMaps(
        {'code': 'DEVICE_NOT_PAIRED', 'message': 'pair first'},
        null,
      );
      expect(error.isPairingRequired, true);
      expect(error.message, 'pair first');
    });
  });

  group('GatewayConnectDecision', () {
    test('协议错误只允许一次 v3 降级', () {
      final error = GatewayErrorInfo.fromMaps(
        {'code': 'PROTOCOL_MISMATCH'},
        null,
      );
      expect(
        GatewayConnectDecision.forError(
          error: error,
          authSource: GatewayAuthSource.gatewayToken,
          hasDeviceToken: false,
          deviceTokenRetryUsed: false,
          legacyProtocolRetryUsed: false,
          remainingBudget: const Duration(seconds: 10),
        ).action,
        GatewayConnectAction.retryLegacyV3,
      );
      expect(
        GatewayConnectDecision.forError(
          error: error,
          authSource: GatewayAuthSource.gatewayToken,
          hasDeviceToken: false,
          deviceTokenRetryUsed: false,
          legacyProtocolRetryUsed: true,
          remainingBudget: const Duration(seconds: 10),
        ).action,
        GatewayConnectAction.fail,
      );
    });

    test('共享 Token 失败仅允许一次 deviceToken 重试', () {
      final error = GatewayErrorInfo.fromMaps({
        'details': {
          'code': 'AUTH_TOKEN_INVALID',
          'canRetryWithDeviceToken': true,
        },
      }, null);
      expect(
        GatewayConnectDecision.forError(
          error: error,
          authSource: GatewayAuthSource.gatewayToken,
          hasDeviceToken: true,
          deviceTokenRetryUsed: false,
          legacyProtocolRetryUsed: false,
          remainingBudget: const Duration(seconds: 10),
        ).action,
        GatewayConnectAction.retryWithDeviceToken,
      );
      expect(
        GatewayConnectDecision.forError(
          error: error,
          authSource: GatewayAuthSource.deviceToken,
          hasDeviceToken: true,
          deviceTokenRetryUsed: true,
          legacyProtocolRetryUsed: false,
          remainingBudget: const Duration(seconds: 10),
        ).action,
        GatewayConnectAction.fail,
      );
    });

    test('retryAfterMs 不能超过总连接预算', () {
      final error = GatewayErrorInfo.fromMaps(
        {'code': 'STARTING', 'retryAfterMs': 1500},
        null,
      );
      expect(
        GatewayConnectDecision.forError(
          error: error,
          authSource: GatewayAuthSource.none,
          hasDeviceToken: false,
          deviceTokenRetryUsed: false,
          legacyProtocolRetryUsed: false,
          remainingBudget: const Duration(seconds: 2),
        ).action,
        GatewayConnectAction.retryAfterDelay,
      );
      expect(
        GatewayConnectDecision.forError(
          error: error,
          authSource: GatewayAuthSource.none,
          hasDeviceToken: false,
          deviceTokenRetryUsed: false,
          legacyProtocolRetryUsed: false,
          remainingBudget: const Duration(seconds: 1),
        ).action,
        GatewayConnectAction.fail,
      );
    });

    test('鉴权错误绝不触发协议降级或延时循环', () {
      final error = GatewayErrorInfo.fromMaps(
        {'code': 'UNAUTHORIZED', 'retryAfterMs': 100},
        null,
      );
      expect(
        GatewayConnectDecision.forError(
          error: error,
          authSource: GatewayAuthSource.deviceToken,
          hasDeviceToken: true,
          deviceTokenRetryUsed: true,
          legacyProtocolRetryUsed: false,
          remainingBudget: const Duration(seconds: 10),
        ).action,
        GatewayConnectAction.fail,
      );
    });
  });

  group('GatewayNodeInvoke', () {
    final fixtures = <String, Map<String, dynamic>>{
      'v3 paramsJSON': {
        'id': 'invoke-v3',
        'nodeId': 'android-v3',
        'command': 'device.echo',
        'paramsJSON': '{"text":"stable"}',
        'timeoutMs': 30000,
      },
      'v4 structured params': {
        'id': 'invoke-v4',
        'nodeId': 'android-v4',
        'command': 'device.echo',
        'params': {'text': 'latest'},
        'timeoutMs': 30000,
        'idempotencyKey': 'future-safe',
        'unknownFutureField': true,
      },
    };

    for (final fixture in fixtures.entries) {
      test('${fixture.key} 可解析并构造结果请求', () {
        final event = NodeFrame.decode(NodeFrame.event(
          'node.invoke.request',
          fixture.value,
        ).encode());
        final invoke = GatewayNodeInvoke.fromPayload(event.payload!);

        expect(invoke.isValid, isTrue);
        expect(invoke.params['text'], isNotEmpty);

        final result = NodeFrame.decode(NodeFrame.request(
          'node.invoke.result',
          {
            'id': invoke.id,
            'nodeId': invoke.nodeId,
            'ok': true,
            'payloadJSON': '{"echo":true}',
          },
        ).encode());
        expect(result.method, 'node.invoke.result');
        expect(result.params?['id'], invoke.id);
        expect(result.params?['ok'], isTrue);
      });
    }
  });
}
