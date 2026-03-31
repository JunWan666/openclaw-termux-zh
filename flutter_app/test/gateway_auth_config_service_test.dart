import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/services/gateway_auth_config_service.dart';

void main() {
  group('GatewayAuthConfigService', () {
    test('extracts gateway auth token from official config path', () {
      const config = '''
{
  "gateway": {
    "auth": {
      "token": "deadbeefcafebabe"
    }
  }
}
''';

      final token = GatewayAuthConfigService.extractGatewayAuthToken(config);

      expect(token, 'deadbeefcafebabe');
    });

    test('resolves env-backed gateway auth token from .env content', () {
      const config = '''
{
  "gateway": {
    "auth": {
      "token": "\${OPENCLAW_GATEWAY_TOKEN}"
    }
  }
}
''';
      const env = '''
OPENCLAW_GATEWAY_TOKEN="feedface1234"
''';

      final token = GatewayAuthConfigService.extractGatewayAuthToken(
        config,
        envContent: env,
      );

      expect(token, 'feedface1234');
    });

    test('falls back to legacy controlUi token when needed', () {
      const config = '''
{
  "gateway": {
    "controlUi": {
      "token": "legacy-token-123"
    }
  }
}
''';

      final token = GatewayAuthConfigService.extractGatewayAuthToken(config);

      expect(token, 'legacy-token-123');
    });

    test('sanitizes noisy suffixes from config token values', () {
      const config = '''
{
  "gateway": {
    "auth": {
      "token": "abcd1234GatewayWS"
    }
  }
}
''';

      final token = GatewayAuthConfigService.extractGatewayAuthToken(config);

      expect(token, 'abcd1234');
    });
  });
}
