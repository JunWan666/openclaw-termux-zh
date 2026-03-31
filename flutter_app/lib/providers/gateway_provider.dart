import 'dart:async';
import 'package:flutter/widgets.dart';
import '../models/gateway_state.dart';
import '../services/gateway_service.dart' as svc;

class GatewayProvider extends ChangeNotifier with WidgetsBindingObserver {
  final svc.GatewayService _gatewayService = svc.GatewayService();
  StreamSubscription? _subscription;
  GatewayState _state = const GatewayState();

  GatewayState get state => _state;

  GatewayProvider() {
    WidgetsBinding.instance.addObserver(this);
    _subscription = _gatewayService.stateStream.listen((state) {
      _state = state;
      notifyListeners();
    });
    // Check if gateway is already running (e.g. after app restart)
    _gatewayService.init();
  }

  Future<void> start() async {
    await _gatewayService.start();
  }

  Future<void> stop() async {
    await _gatewayService.stop();
  }

  Future<bool> checkHealth() async {
    return _gatewayService.checkHealth();
  }

  Future<void> syncState() async {
    await _gatewayService.syncStateFromSystem();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      syncState();
    }
  }

  Future<void> applyConfigChanges({String source = 'configuration'}) async {
    await _gatewayService.applyConfigChanges(source: source);
  }

  void clearLogs() {
    _gatewayService.clearLogs();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _gatewayService.dispose();
    super.dispose();
  }
}
