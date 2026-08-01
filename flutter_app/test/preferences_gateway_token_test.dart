import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('预发布版本开关默认关闭并可持久化开启', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();

    expect(prefs.showPrereleaseVersions, isFalse);

    prefs.showPrereleaseVersions = true;
    expect(prefs.showPrereleaseVersions, isTrue);
    expect(PreferencesService.showPrereleaseVersionsChanges.value, isTrue);
  });

  test('旧版单字符串 deviceToken 保持可读', () async {
    SharedPreferences.setMockInitialValues({
      'node_device_token': 'legacy-token',
    });
    final prefs = PreferencesService();
    await prefs.init();

    expect(prefs.nodeDeviceToken, 'legacy-token');
    expect(prefs.nodeDeviceTokenEndpoint, isNull);
    expect(prefs.nodeDeviceTokenScopes, isEmpty);
  });

  test('新版 deviceToken 保存 endpoint、role 与 scopes', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();

    prefs.saveNodeDeviceToken(
      token: 'scoped-token',
      endpoint: '127.0.0.1:18789',
      role: 'node',
      scopes: const ['node.device', 'node.invoke'],
    );

    expect(prefs.nodeDeviceToken, 'scoped-token');
    expect(prefs.nodeDeviceTokenEndpoint, '127.0.0.1:18789');
    expect(prefs.nodeDeviceTokenRole, 'node');
    expect(prefs.nodeDeviceTokenScopes, ['node.device', 'node.invoke']);

    prefs.clearNodeDeviceToken();
    expect(prefs.nodeDeviceToken, isNull);
    expect(prefs.nodeDeviceTokenEndpoint, isNull);
    expect(prefs.nodeDeviceTokenRole, isNull);
    expect(prefs.nodeDeviceTokenScopes, isEmpty);
  });

  test('Web dashboard remembers only supported loopback hosts', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = PreferencesService();
    await prefs.init();

    prefs.webDashboardPreferredHost = 'localhost';
    expect(prefs.webDashboardPreferredHost, 'localhost');

    prefs.webDashboardPreferredHost = '127.0.0.1';
    expect(prefs.webDashboardPreferredHost, '127.0.0.1');

    prefs.webDashboardPreferredHost = 'example.com';
    expect(prefs.webDashboardPreferredHost, isNull);
  });
}
