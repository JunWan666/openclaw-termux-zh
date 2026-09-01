import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/constants.dart';
import 'package:openclaw/services/message_platform_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(AppConstants.channelName);
  late List<String> commands;

  setUp(() {
    commands = <String>[];
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'setupDirs':
        case 'writeResolv':
          return true;
        case 'runInProot':
          final arguments = Map<String, dynamic>.from(call.arguments as Map);
          commands.add(arguments['command'] as String);
          return '';
        default:
          throw MissingPluginException('Unhandled method: ${call.method}');
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('QQ configuration never installs the plugin implicitly', () async {
    await MessagePlatformConfigService.configureQqbot(
      appId: '123456',
      appSecret: 'secret',
    );

    expect(commands, hasLength(1));
    expect(commands.single, contains('openclaw channels add --channel qqbot'));
    expect(commands.single, isNot(contains('plugins install')));
  });
}
