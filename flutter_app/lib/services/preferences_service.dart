import 'package:shared_preferences/shared_preferences.dart';

import 'dashboard_url_resolver.dart';

class PreferencesService {
  static const _keyAutoStart = 'auto_start_gateway';
  static const _keySetupComplete = 'setup_complete';
  static const _keyFirstRun = 'first_run';
  static const _keyPendingSetupCompletionChoice =
      'pending_setup_completion_choice';
  static const _keyDashboardUrl = 'dashboard_url';
  static const _keyWebDashboardScale = 'web_dashboard_scale';
  static const _keyLocaleCode = 'locale_code';
  static const _keyBonjourEnabled = 'bonjour_enabled';
  static const _keyNodeEnabled = 'node_enabled';
  static const _keyNodeDeviceToken = 'node_device_token';
  static const _keyNodeGatewayHost = 'node_gateway_host';
  static const _keyNodeGatewayPort = 'node_gateway_port';
  static const _keyNodePublicKey = 'node_ed25519_public';
  static const _keyNodeGatewayToken = 'node_gateway_token';
  static const _keyLastAppVersion = 'last_app_version';
  static const _keyQqbotAppId = 'qqbot_app_id';
  static const _keyQqbotAppSecret = 'qqbot_app_secret';
  static const _keyLocalModelMaxCpuCores = 'local_model_max_cpu_cores';
  static const _keyLocalModelMemoryLimitMiB = 'local_model_memory_limit_mib';
  static const _keyLocalModelPerformanceMode = 'local_model_performance_mode';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  bool get autoStartGateway => _prefs.getBool(_keyAutoStart) ?? false;
  set autoStartGateway(bool value) => _prefs.setBool(_keyAutoStart, value);

  bool get setupComplete => _prefs.getBool(_keySetupComplete) ?? false;
  set setupComplete(bool value) => _prefs.setBool(_keySetupComplete, value);

  bool get isFirstRun => _prefs.getBool(_keyFirstRun) ?? true;
  set isFirstRun(bool value) => _prefs.setBool(_keyFirstRun, value);

  bool get pendingSetupCompletionChoice =>
      _prefs.getBool(_keyPendingSetupCompletionChoice) ?? false;
  set pendingSetupCompletionChoice(bool value) =>
      _prefs.setBool(_keyPendingSetupCompletionChoice, value);

  String? get dashboardUrl {
    final rawValue = _prefs.getString(_keyDashboardUrl);
    final normalized = DashboardUrlResolver.normalizeDashboardUrl(rawValue);
    if (rawValue != normalized) {
      if (normalized != null) {
        _prefs.setString(_keyDashboardUrl, normalized);
      } else {
        _prefs.remove(_keyDashboardUrl);
      }
    }
    return normalized;
  }

  set dashboardUrl(String? value) {
    final normalized = DashboardUrlResolver.normalizeDashboardUrl(value);
    if (normalized != null) {
      _prefs.setString(_keyDashboardUrl, normalized);
    } else {
      _prefs.remove(_keyDashboardUrl);
    }
  }

  double get webDashboardScale {
    final value = _prefs.getDouble(_keyWebDashboardScale);
    if (value == null || value <= 0) {
      return 1.0;
    }
    return value;
  }

  set webDashboardScale(double value) {
    if (value <= 0 || (value - 1.0).abs() < 0.0001) {
      _prefs.remove(_keyWebDashboardScale);
    } else {
      _prefs.setDouble(_keyWebDashboardScale, value);
    }
  }

  String? get localeCode => _prefs.getString(_keyLocaleCode);
  set localeCode(String? value) {
    if (value != null && value.isNotEmpty) {
      _prefs.setString(_keyLocaleCode, value);
    } else {
      _prefs.remove(_keyLocaleCode);
    }
  }

  bool get bonjourEnabled => _prefs.getBool(_keyBonjourEnabled) ?? false;
  set bonjourEnabled(bool value) => _prefs.setBool(_keyBonjourEnabled, value);

  bool get nodeEnabled => _prefs.getBool(_keyNodeEnabled) ?? false;
  set nodeEnabled(bool value) => _prefs.setBool(_keyNodeEnabled, value);

  String? get nodeDeviceToken => _prefs.getString(_keyNodeDeviceToken);
  set nodeDeviceToken(String? value) {
    if (value != null) {
      _prefs.setString(_keyNodeDeviceToken, value);
    } else {
      _prefs.remove(_keyNodeDeviceToken);
    }
  }

  String? get nodeGatewayHost => _prefs.getString(_keyNodeGatewayHost);
  set nodeGatewayHost(String? value) {
    if (value != null) {
      _prefs.setString(_keyNodeGatewayHost, value);
    } else {
      _prefs.remove(_keyNodeGatewayHost);
    }
  }

  String? get nodePublicKey => _prefs.getString(_keyNodePublicKey);

  String? get nodeGatewayToken => _prefs.getString(_keyNodeGatewayToken);
  set nodeGatewayToken(String? value) {
    if (value != null && value.isNotEmpty) {
      _prefs.setString(_keyNodeGatewayToken, value);
    } else {
      _prefs.remove(_keyNodeGatewayToken);
    }
  }

  String? get lastAppVersion => _prefs.getString(_keyLastAppVersion);
  set lastAppVersion(String? value) {
    if (value != null) {
      _prefs.setString(_keyLastAppVersion, value);
    } else {
      _prefs.remove(_keyLastAppVersion);
    }
  }

  String? get qqbotAppId => _prefs.getString(_keyQqbotAppId);
  set qqbotAppId(String? value) {
    if (value != null && value.isNotEmpty) {
      _prefs.setString(_keyQqbotAppId, value);
    } else {
      _prefs.remove(_keyQqbotAppId);
    }
  }

  String? get qqbotAppSecret => _prefs.getString(_keyQqbotAppSecret);
  set qqbotAppSecret(String? value) {
    if (value != null && value.isNotEmpty) {
      _prefs.setString(_keyQqbotAppSecret, value);
    } else {
      _prefs.remove(_keyQqbotAppSecret);
    }
  }

  int get localModelMaxCpuCores =>
      (_prefs.getInt(_keyLocalModelMaxCpuCores) ?? 0).clamp(0, 128);
  set localModelMaxCpuCores(int value) {
    final normalized = value.clamp(0, 128);
    if (normalized <= 0) {
      _prefs.remove(_keyLocalModelMaxCpuCores);
    } else {
      _prefs.setInt(_keyLocalModelMaxCpuCores, normalized);
    }
  }

  int get localModelMemoryLimitMiB =>
      (_prefs.getInt(_keyLocalModelMemoryLimitMiB) ?? 0).clamp(0, 262144);
  set localModelMemoryLimitMiB(int value) {
    final normalized = value.clamp(0, 262144);
    if (normalized <= 0) {
      _prefs.remove(_keyLocalModelMemoryLimitMiB);
    } else {
      _prefs.setInt(_keyLocalModelMemoryLimitMiB, normalized);
    }
  }

  String get localModelPerformanceMode =>
      _prefs.getString(_keyLocalModelPerformanceMode) ?? 'balanced';
  set localModelPerformanceMode(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == 'balanced') {
      _prefs.remove(_keyLocalModelPerformanceMode);
    } else {
      _prefs.setString(_keyLocalModelPerformanceMode, normalized);
    }
  }

  int? get nodeGatewayPort {
    final val = _prefs.getInt(_keyNodeGatewayPort);
    return val;
  }

  set nodeGatewayPort(int? value) {
    if (value != null) {
      _prefs.setInt(_keyNodeGatewayPort, value);
    } else {
      _prefs.remove(_keyNodeGatewayPort);
    }
  }
}
