import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/models/openclaw_install_options.dart';

void main() {
  test('OpenClaw installs use the persistent npm cache mount', () {
    const options = OpenClawInstallOptions();

    expect(
      options.installEnvironment['npm_config_cache'],
      '/root/.cache/npm',
    );
    expect(options.npmFlags, contains('--prefer-offline'));
  });
}
