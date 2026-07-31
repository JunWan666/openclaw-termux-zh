import 'dart:convert';

/// Gateway 客户端支持的协议范围。
class GatewayProtocolVersionRange {
  static const compatible = GatewayProtocolVersionRange(3, 4);
  static const legacyV3 = GatewayProtocolVersionRange(3, 3);

  final int min;
  final int max;

  const GatewayProtocolVersionRange(this.min, this.max)
      : assert(min > 0),
        assert(max >= min);

  bool supports(int version) => version >= min && version <= max;
}

enum GatewayAuthSource { none, gatewayToken, deviceToken }

/// 当前握手采用的认证来源，以及设备 Token 的授权上下文。
class GatewayAuthState {
  final GatewayAuthSource source;
  final String? token;
  final String role;
  final List<String> scopes;

  const GatewayAuthState({
    required this.source,
    required this.token,
    required this.role,
    required this.scopes,
  });
}

/// hello-ok 中与客户端后续行为有关的数据。
class GatewayHello {
  final int? protocol;
  final String? role;
  final List<String> scopes;
  final String? deviceToken;
  final String? mainSessionKey;
  final Map<String, dynamic> policy;
  final Map<String, dynamic> features;
  final Map<String, dynamic> raw;

  const GatewayHello({
    required this.protocol,
    required this.role,
    required this.scopes,
    required this.deviceToken,
    required this.mainSessionKey,
    required this.policy,
    required this.features,
    required this.raw,
  });

  factory GatewayHello.fromPayload(Map<String, dynamic> payload) {
    final auth = _map(payload['auth']);
    final sessionDefaults = _map(payload['sessionDefaults']);
    return GatewayHello(
      protocol: _int(payload['protocol']),
      role: _string(auth['role']) ?? _string(payload['role']),
      scopes: _strings(auth['scopes'] ?? payload['scopes']),
      deviceToken: _string(auth['deviceToken']),
      mainSessionKey: _string(sessionDefaults['mainSessionKey']),
      policy: _map(payload['policy']),
      features: _map(payload['features']),
      raw: Map<String, dynamic>.from(payload),
    );
  }
}

/// 兼容 v3 顶层错误与 v4 details 嵌套错误。
class GatewayErrorInfo {
  final String code;
  final String message;
  final String? reason;
  final String? recommendedNextStep;
  final bool canRetryWithDeviceToken;
  final int? retryAfterMs;
  final Map<String, dynamic> details;

  const GatewayErrorInfo({
    required this.code,
    required this.message,
    required this.reason,
    required this.recommendedNextStep,
    required this.canRetryWithDeviceToken,
    required this.retryAfterMs,
    required this.details,
  });

  factory GatewayErrorInfo.fromMaps(
    Map<String, dynamic>? error,
    Map<String, dynamic>? payload,
  ) {
    final source = <String, dynamic>{...?payload, ...?error};
    final details = _map(source['details']);
    return GatewayErrorInfo(
      code: (details['code'] ?? source['code'] ?? '').toString(),
      message: (source['message'] ?? details['message'] ?? 'Connect failed')
          .toString(),
      reason: _string(details['reason'] ?? source['reason']),
      recommendedNextStep: _string(
        details['recommendedNextStep'] ?? source['recommendedNextStep'],
      ),
      canRetryWithDeviceToken: details['canRetryWithDeviceToken'] == true ||
          source['canRetryWithDeviceToken'] == true,
      retryAfterMs: _int(details['retryAfterMs'] ?? source['retryAfterMs']),
      details: details,
    );
  }

  bool get isProtocolMismatch {
    final normalized = code.toUpperCase();
    return normalized == 'PROTOCOL_MISMATCH' ||
        normalized == 'UNSUPPORTED_PROTOCOL' ||
        normalized == 'PROTOCOL_VERSION_MISMATCH';
  }

  bool get isPairingRequired {
    final normalized = code.toUpperCase();
    return normalized == 'NOT_PAIRED' || normalized == 'DEVICE_NOT_PAIRED';
  }

  bool get isAuthenticationFailure {
    final normalized = code.toUpperCase();
    return normalized.contains('TOKEN') ||
        normalized.contains('AUTH') ||
        normalized == 'UNAUTHORIZED' ||
        normalized == 'FORBIDDEN';
  }
}

/// v3/v4 共用的 Node Invoke 载荷；结构化 params 用于兼容后续协议扩展。
class GatewayNodeInvoke {
  const GatewayNodeInvoke({
    required this.id,
    required this.nodeId,
    required this.command,
    required this.params,
    required this.timeoutMs,
    required this.idempotencyKey,
  });

  final String? id;
  final String? nodeId;
  final String? command;
  final Map<String, dynamic> params;
  final int? timeoutMs;
  final String? idempotencyKey;

  bool get isValid => id != null && command != null;

  factory GatewayNodeInvoke.fromPayload(Map<String, dynamic> payload) {
    Map<String, dynamic> params = const {};
    final paramsJson = _string(payload['paramsJSON']);
    if (paramsJson != null) {
      try {
        final decoded = jsonDecode(paramsJson);
        if (decoded is Map) params = Map<String, dynamic>.from(decoded);
      } on FormatException {
        // 与旧实现一致：无效参数交给 capability 以空对象处理。
      }
    } else if (payload['params'] is Map) {
      params = Map<String, dynamic>.from(payload['params'] as Map);
    }
    return GatewayNodeInvoke(
      id: _nonEmptyString(payload['id']),
      nodeId: _nonEmptyString(payload['nodeId']),
      command: _nonEmptyString(payload['command']),
      params: params,
      timeoutMs: _int(payload['timeoutMs']),
      idempotencyKey: _nonEmptyString(payload['idempotencyKey']),
    );
  }
}

enum GatewayConnectAction {
  fail,
  requestPairing,
  retryWithDeviceToken,
  retryLegacyV3,
  retryAfterDelay,
}

class GatewayConnectDecision {
  final GatewayConnectAction action;
  final Duration? delay;

  const GatewayConnectDecision(this.action, {this.delay});

  factory GatewayConnectDecision.forError({
    required GatewayErrorInfo error,
    required GatewayAuthSource authSource,
    required bool hasDeviceToken,
    required bool deviceTokenRetryUsed,
    required bool legacyProtocolRetryUsed,
    required Duration remainingBudget,
  }) {
    if (error.isProtocolMismatch && !legacyProtocolRetryUsed) {
      return const GatewayConnectDecision(
        GatewayConnectAction.retryLegacyV3,
      );
    }
    if (error.isPairingRequired) {
      return const GatewayConnectDecision(
        GatewayConnectAction.requestPairing,
      );
    }
    if (authSource == GatewayAuthSource.gatewayToken &&
        hasDeviceToken &&
        !deviceTokenRetryUsed &&
        (error.canRetryWithDeviceToken || error.isAuthenticationFailure)) {
      return const GatewayConnectDecision(
        GatewayConnectAction.retryWithDeviceToken,
      );
    }
    final retryAfterMs = error.retryAfterMs;
    if (!error.isAuthenticationFailure &&
        retryAfterMs != null &&
        retryAfterMs > 0 &&
        retryAfterMs <= remainingBudget.inMilliseconds) {
      return GatewayConnectDecision(
        GatewayConnectAction.retryAfterDelay,
        delay: Duration(milliseconds: retryAfterMs),
      );
    }
    return const GatewayConnectDecision(GatewayConnectAction.fail);
  }
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<String> _strings(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const [];

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String? _string(Object? value) => value is String ? value : null;

String? _nonEmptyString(Object? value) {
  final normalized = _string(value)?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
