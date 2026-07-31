import 'dart:async';
import 'dart:convert';
import '../constants.dart';
import '../models/node_frame.dart';
import '../models/gateway_protocol.dart';
import '../models/node_state.dart';
import 'dashboard_url_resolver.dart';
import 'gateway_auth_config_service.dart';
import 'native_bridge.dart';
import 'node_identity_service.dart';
import 'node_ws_service.dart';
import 'preferences_service.dart';

class NodeService {
  final NodeIdentityService _identity = NodeIdentityService();
  final NodeWsService _ws = NodeWsService();
  final _stateController = StreamController<NodeState>.broadcast();
  StreamSubscription? _frameSubscription;

  NodeState _state = const NodeState();
  final Map<String, Future<NodeFrame> Function(String, Map<String, dynamic>)>
      _capabilityHandlers = {};
  String? _gatewayAuthToken;
  bool _isAppInForeground = true;
  bool _deviceTokenRetryUsed = false;
  bool _legacyProtocolRetryUsed = false;
  DateTime? _connectStartedAt;

  static const _connectBudget = Duration(seconds: 30);

  void setAppInForeground(bool value) {
    _isAppInForeground = value;
  }

  Stream<NodeState> get stateStream => _stateController.stream;
  NodeState get state => _state;
  bool get isConnectionStale => _ws.isStale;

  void clearCachedToken() => _gatewayAuthToken = null;

  void _updateState(NodeState newState) {
    _state = newState;
    _stateController.add(_state);
  }

  void _log(String message) {
    final logs = [..._state.logs, message];
    if (logs.length > 500) {
      logs.removeRange(0, logs.length - 500);
    }
    _updateState(_state.copyWith(logs: logs));
  }

  void registerCapability(
      String name,
      List<String> commands,
      Future<NodeFrame> Function(String command, Map<String, dynamic> params)
          handler) {
    for (final cmd in commands) {
      _capabilityHandlers[cmd] = handler;
    }
  }

  Future<void> init() async {
    await _identity.init();
    _updateState(_state.copyWith(deviceId: _identity.deviceId));
    _log('[NODE] Device ID: ${_identity.deviceId.substring(0, 12)}...');
  }

  Future<void> connect({String? host, int? port}) async {
    final prefs = PreferencesService();
    await prefs.init();

    final targetHost =
        host ?? prefs.nodeGatewayHost ?? AppConstants.gatewayHost;
    final targetPort =
        port ?? prefs.nodeGatewayPort ?? AppConstants.gatewayPort;

    _deviceTokenRetryUsed = false;
    _legacyProtocolRetryUsed = false;
    _connectStartedAt = DateTime.now();

    _updateState(_state.copyWith(
      status: NodeStatus.connecting,
      clearError: true,
      gatewayHost: targetHost,
      gatewayPort: targetPort,
    ));
    _log('[NODE] Connecting to $targetHost:$targetPort...');

    _frameSubscription?.cancel();
    _frameSubscription = _ws.frameStream.listen(_onFrame);

    try {
      await _ws.connect(targetHost, targetPort);
      _log('[NODE] WebSocket connected, awaiting challenge...');
    } catch (e) {
      _updateState(_state.copyWith(
        status: NodeStatus.error,
        errorMessage: 'Connection failed: $e',
      ));
      _log('[NODE] Connection failed: $e');
    }
  }

  void _onFrame(NodeFrame frame) {
    if (frame.isEvent) {
      _handleEvent(frame);
    }
  }

  Future<void> _handleEvent(NodeFrame frame) async {
    switch (frame.event) {
      case '_disconnected':
        if (_state.status != NodeStatus.disabled) {
          _updateState(_state.copyWith(
            status: NodeStatus.disconnected,
            clearConnectedAt: true,
          ));
          _log('[NODE] Disconnected, will retry...');
        }
        break;

      case 'connect.challenge':
        _updateState(_state.copyWith(status: NodeStatus.challenging));
        final nonce = frame.payload?['nonce'] as String?;
        if (nonce == null) {
          _log('[NODE] Challenge missing nonce');
          return;
        }
        _log('[NODE] Challenge received, signing...');
        try {
          await _sendConnect(
            nonce,
            protocolRange: _legacyProtocolRetryUsed
                ? GatewayProtocolVersionRange.legacyV3
                : GatewayProtocolVersionRange.compatible,
            forceDeviceToken: _deviceTokenRetryUsed,
          );
        } catch (e) {
          _log('[NODE] Challenge/connect error: $e');
          _updateState(_state.copyWith(
            status: NodeStatus.error,
            errorMessage: '$e',
          ));
        }
        break;

      case 'node.invoke.request':
        await _handleInvokeRequest(frame.payload ?? {});
        break;
    }
  }

  /// Resolve the gateway auth token from available sources:
  /// 1. Manually entered token (for remote gateways)
  /// 2. openclaw.json / .env persisted config (for local gateway)
  /// 3. Dashboard URL fragment fallback
  Future<String?> _readGatewayToken() async {
    final prefs = PreferencesService();
    await prefs.init();

    // 1. Manual token (user-provided for remote gateway)
    final manualToken = prefs.nodeGatewayToken;
    if (manualToken != null && manualToken.isNotEmpty) {
      _log('[NODE] Using manually configured gateway token');
      return manualToken;
    }

    // 2. Prefer the persisted gateway auth token from config/.env.
    final configuredToken =
        await GatewayAuthConfigService.readGatewayAuthToken();
    if (configuredToken != null && configuredToken.isNotEmpty) {
      _log('[NODE] Gateway token loaded from openclaw.json');
      return configuredToken;
    }

    // 3. Extract from local dashboard URL
    final dashboardUrl = prefs.dashboardUrl;
    if (dashboardUrl != null) {
      final token = DashboardUrlResolver.extractToken(dashboardUrl);
      if (token != null) {
        _log('[NODE] Gateway token extracted from dashboard URL');
        return token;
      }
    }

    _log('[NODE] No gateway token available');
    return null;
  }

  /// 发送 connect 请求。默认声明 v3..v4，仅在明确协议不匹配时降级 v3。
  Future<void> _sendConnect(
    String nonce, {
    GatewayProtocolVersionRange protocolRange =
        GatewayProtocolVersionRange.compatible,
    bool forceDeviceToken = false,
  }) async {
    final prefs = PreferencesService();
    await prefs.init();
    final endpoint = '${_state.gatewayHost}:${_state.gatewayPort}';
    final storedTokenEndpoint = prefs.nodeDeviceTokenEndpoint;
    // 新格式 Token 只用于签发它的 Gateway；旧格式无端点 Token 继续兼容。
    final deviceToken =
        storedTokenEndpoint == null || storedTokenEndpoint == endpoint
            ? prefs.nodeDeviceToken
            : null;

    // For local connections, read the gateway auth token from dashboard URL
    _gatewayAuthToken ??= await _readGatewayToken();

    // 首次优先共享 Gateway Token；服务端明确允许时才用 deviceToken 重试。
    final authToken =
        forceDeviceToken ? deviceToken : (_gatewayAuthToken ?? deviceToken);
    final authSource = authToken == null
        ? GatewayAuthSource.none
        : (forceDeviceToken || _gatewayAuthToken == null)
            ? GatewayAuthSource.deviceToken
            : GatewayAuthSource.gatewayToken;

    const clientId = 'node-host';
    const clientMode = 'node';
    final useDeviceTokenContext =
        authSource == GatewayAuthSource.deviceToken && deviceToken != null;
    final role = useDeviceTokenContext
        ? (prefs.nodeDeviceTokenRole ?? AppConstants.nodeRole)
        : AppConstants.nodeRole;
    final storedScopes = prefs.nodeDeviceTokenScopes;
    final scopes = useDeviceTokenContext && storedScopes.isNotEmpty
        ? storedScopes
        : const <String>['node.device'];
    final signedAtMs = DateTime.now().millisecondsSinceEpoch;

    // Build the structured payload the gateway verifies:
    // "v2|deviceId|clientId|clientMode|role|scopes|signedAtMs|token|nonce"
    final authPayload = _identity.buildAuthPayload(
      clientId: clientId,
      clientMode: clientMode,
      role: role,
      scopes: scopes,
      signedAtMs: signedAtMs,
      token: authToken,
      nonce: nonce,
    );
    final signature = await _identity.signPayload(authPayload);

    // Build caps (unique capability names) and commands from registered handlers
    final commands = _capabilityHandlers.keys.toList();
    final caps = commands.map((c) => c.split('.').first).toSet().toList();
    _log('[NODE] Declaring ${commands.length} commands: $commands');

    final connectFrame = NodeFrame.request('connect', {
      'minProtocol': protocolRange.min,
      'maxProtocol': protocolRange.max,
      'client': {
        'id': clientId,
        'displayName': 'OpenClawX Node',
        'version': AppConstants.version,
        'platform': 'android',
        'deviceFamily': 'Android',
        'mode': clientMode,
      },
      'role': role,
      'scopes': scopes,
      'caps': caps,
      'commands': commands,
      'permissions': <String, dynamic>{},
      if (authToken != null) 'auth': {'token': authToken},
      'device': {
        'id': _identity.deviceId,
        'publicKey': _identity.publicKeyBase64Url,
        'signature': signature,
        'nonce': nonce,
        'signedAt': signedAtMs,
      },
    });

    _log(
        '[NODE] Connect frame protocol=${protocolRange.min}..${protocolRange.max} '
        'auth=${authSource.name} caps=$caps commands=$commands');
    _log('[NODE] Connect frame platform=android deviceFamily=Android');
    final response = await _ws.sendRequest(connectFrame);
    _log(
        '[NODE] Connect response ok=${response.isOk} payload=${response.payload}');

    if (response.isOk) {
      final hello = GatewayHello.fromPayload(response.payload ?? const {});
      if (hello.protocol != null && !protocolRange.supports(hello.protocol!)) {
        _ws.pauseReconnect();
        _updateState(_state.copyWith(
          status: NodeStatus.error,
          errorMessage: 'Gateway negotiated unsupported protocol '
              '${hello.protocol}',
        ));
        return;
      }
      if (hello.deviceToken != null) {
        prefs.saveNodeDeviceToken(
          token: hello.deviceToken!,
          endpoint: endpoint,
          role: hello.role ?? role,
          scopes: hello.scopes.isEmpty ? scopes : hello.scopes,
        );
      }
      prefs.nodeMainSessionKey = hello.mainSessionKey;
      _log('[NODE] Gateway hello protocol=${hello.protocol ?? 'legacy'} '
          'role=${hello.role ?? role} scopes=${hello.scopes} '
          'features=${hello.features.keys.toList()}');
      _onConnected(response);
    } else if (response.isError) {
      final error = GatewayErrorInfo.fromMaps(response.error, response.payload);
      final elapsed = DateTime.now().difference(_connectStartedAt!);
      final remaining = _connectBudget - elapsed;
      final decision = GatewayConnectDecision.forError(
        error: error,
        authSource: authSource,
        hasDeviceToken: deviceToken != null && deviceToken.isNotEmpty,
        deviceTokenRetryUsed: _deviceTokenRetryUsed,
        legacyProtocolRetryUsed: _legacyProtocolRetryUsed,
        remainingBudget: remaining.isNegative ? Duration.zero : remaining,
      );
      _log('[NODE] Connect error: ${error.code} - ${error.message} '
          'next=${error.recommendedNextStep ?? decision.action.name}');

      switch (decision.action) {
        case GatewayConnectAction.retryLegacyV3:
          _legacyProtocolRetryUsed = true;
          await _sendConnect(
            nonce,
            protocolRange: GatewayProtocolVersionRange.legacyV3,
            forceDeviceToken: forceDeviceToken,
          );
          return;
        case GatewayConnectAction.retryWithDeviceToken:
          _deviceTokenRetryUsed = true;
          await _sendConnect(
            nonce,
            protocolRange: protocolRange,
            forceDeviceToken: true,
          );
          return;
        case GatewayConnectAction.retryAfterDelay:
          await Future.delayed(decision.delay!);
          await _sendConnect(
            nonce,
            protocolRange: protocolRange,
            forceDeviceToken: forceDeviceToken,
          );
          return;
        case GatewayConnectAction.requestPairing:
          _log('[NODE] Not paired, requesting pairing...');
          await _requestPairing();
          return;
        case GatewayConnectAction.fail:
          if (authSource == GatewayAuthSource.deviceToken &&
              error.isAuthenticationFailure) {
            prefs.clearNodeDeviceToken();
          }
          if (error.isAuthenticationFailure) {
            _ws.pauseReconnect();
          }
          _updateState(_state.copyWith(
            status: NodeStatus.error,
            errorMessage: error.message,
          ));
          return;
      }
    }
  }

  void _onConnected(NodeFrame frame) {
    _updateState(_state.copyWith(
      status: NodeStatus.paired,
      connectedAt: DateTime.now(),
      clearError: true,
      clearPairingCode: true,
    ));
    _log('[NODE] Paired and connected');

    // Send capabilities advertisement — include both 'capabilities' (legacy)
    // and 'commands' (matching the connect frame format) so the gateway can
    // discover node commands regardless of which field it checks (#56).
    final capabilities = _capabilityHandlers.keys.toList();
    final caps = capabilities.map((c) => c.split('.').first).toSet().toList();
    _ws.send(NodeFrame.event('node.capabilities', {
      'deviceId': _identity.deviceId,
      'capabilities': capabilities,
      'commands': capabilities,
      'caps': caps,
    }));
  }

  Future<void> _requestPairing() async {
    _updateState(_state.copyWith(status: NodeStatus.pairing));
    _log('[NODE] Requesting pairing...');

    try {
      final pairReq = NodeFrame.request('node.pair.request', {
        'deviceId': _identity.deviceId,
      });
      final response = await _ws.sendRequest(
        pairReq,
        timeout: const Duration(milliseconds: AppConstants.pairingTimeoutMs),
      );

      if (response.isError) {
        final errPayload = response.payload ?? response.error ?? {};
        _updateState(_state.copyWith(
          status: NodeStatus.error,
          errorMessage: errPayload['message'] as String? ?? 'Pairing failed',
        ));
        _log('[NODE] Pairing error: $errPayload');
        return;
      }

      final respPayload = response.payload ?? {};
      final code = respPayload['code'] as String?;
      final token = respPayload['token'] as String? ??
          (respPayload['auth'] as Map?)?['deviceToken'] as String?;

      if (token != null) {
        final prefs = PreferencesService();
        await prefs.init();
        prefs.saveNodeDeviceToken(
          token: token,
          endpoint: '${_state.gatewayHost}:${_state.gatewayPort}',
          role: AppConstants.nodeRole,
          scopes: const ['node.device'],
        );
        _log('[NODE] Pairing approved, token received');
        await Future.delayed(const Duration(milliseconds: 500));
        await _ws.disconnect();
        await connect();
        return;
      }

      if (code != null) {
        _updateState(_state.copyWith(pairingCode: code));
        _log('[NODE] Pairing code: $code');

        // Auto-approve if connecting to localhost
        final isLocal = _state.gatewayHost == '127.0.0.1' ||
            _state.gatewayHost == 'localhost';
        if (isLocal) {
          _log('[NODE] Local gateway detected, auto-approving...');
          try {
            await NativeBridge.runInProot('openclaw nodes approve $code');
            _log('[NODE] Auto-approve command sent');
            await Future.delayed(const Duration(milliseconds: 500));
            await _ws.disconnect();
            await connect();
          } catch (e) {
            _log('[NODE] Auto-approve failed: $e (user must approve manually)');
          }
        }
      }
    } catch (e) {
      _updateState(_state.copyWith(
        status: NodeStatus.error,
        errorMessage: 'Pairing timeout: $e',
      ));
      _log('[NODE] Pairing failed: $e');
    }
  }

  /// Handle a node.invoke.request event from the gateway.
  /// The gateway sends: event "node.invoke.request" with payload:
  ///   {id, nodeId, command, paramsJSON, timeoutMs}
  /// We must respond by sending a request "node.invoke.result" with:
  ///   {id, nodeId, ok, payload/payloadJSON, error}
  Future<void> _handleInvokeRequest(Map<String, dynamic> invokePayload) async {
    final invoke = GatewayNodeInvoke.fromPayload(invokePayload);
    final requestId = invoke.id;
    final command = invoke.command;
    final nodeId = invoke.nodeId ?? _identity.deviceId;

    if (!invoke.isValid || requestId == null || command == null) {
      _log('[NODE] Invoke missing id or command');
      return;
    }

    _log('[NODE] Invoke: $command');

    final commandParams = invoke.params;

    // Commands that require Activity in foreground (camera, screen, sensor, flash, location)
    const foregroundCommands = [
      'camera',
      'screen',
      'sensor',
      'flash',
      'location'
    ];
    final commandPrefix = command.split('.').first;
    if (foregroundCommands.contains(commandPrefix) && !_isAppInForeground) {
      _log('[NODE] App backgrounded, bringing to foreground for $command');
      try {
        await NativeBridge.bringToForeground();
        await Future.delayed(const Duration(milliseconds: 800));
      } catch (e) {
        _log('[NODE] Failed to bring app to foreground: $e');
        _ws.sendRequest(NodeFrame.request('node.invoke.result', {
          'id': requestId,
          'nodeId': nodeId,
          'ok': false,
          'error': {
            'code': 'APP_BACKGROUNDED',
            'message': 'Cannot bring app to foreground for $command',
          },
        }));
        return;
      }
    }

    final handler = _capabilityHandlers[command];
    if (handler == null) {
      _log('[NODE] Unknown command: $command');
      _ws.sendRequest(NodeFrame.request('node.invoke.result', {
        'id': requestId,
        'nodeId': nodeId,
        'ok': false,
        'error': {
          'code': 'NOT_SUPPORTED',
          'message': 'Capability $command not available',
        },
      }));
      return;
    }

    try {
      final result = await handler(command, commandParams);
      final resultPayload = <String, dynamic>{
        'id': requestId,
        'nodeId': nodeId,
      };
      if (result.isError) {
        resultPayload['ok'] = false;
        resultPayload['error'] = result.error;
      } else {
        resultPayload['ok'] = true;
        if (result.payload != null) {
          resultPayload['payloadJSON'] = jsonEncode(result.payload);
        }
      }
      _ws.sendRequest(NodeFrame.request('node.invoke.result', resultPayload));
      _log('[NODE] Invoke result sent for $command');
    } catch (e) {
      _ws.sendRequest(NodeFrame.request('node.invoke.result', {
        'id': requestId,
        'nodeId': nodeId,
        'ok': false,
        'error': {
          'code': 'INVOKE_ERROR',
          'message': '$e',
        },
      }));
    }
  }

  Future<void> disconnect() async {
    _frameSubscription?.cancel();
    await _ws.disconnect();
    _updateState(_state.copyWith(
      status: NodeStatus.disconnected,
      clearConnectedAt: true,
      clearPairingCode: true,
    ));
    _log('[NODE] Disconnected');
  }

  Future<void> disable() async {
    await disconnect();
    _updateState(NodeState(
      status: NodeStatus.disabled,
      logs: _state.logs,
      deviceId: _state.deviceId,
    ));
    _log('[NODE] Node disabled');
  }

  void dispose() {
    _frameSubscription?.cancel();
    _ws.dispose();
    _stateController.close();
  }
}
