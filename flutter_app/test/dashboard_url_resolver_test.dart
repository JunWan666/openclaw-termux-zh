import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/services/dashboard_url_resolver.dart';

void main() {
  group('DashboardUrlResolver', () {
    test('extracts explicit dashboard token url from localhost log output', () {
      final url = DashboardUrlResolver.extractDashboardUrlFromText(
        'Dashboard ready: http://127.0.0.1:18789/#token=abc123def456',
      );

      expect(url, 'http://127.0.0.1:18789/#token=abc123def456');
    });

    test('normalizes token url for alternate hosts', () {
      final url = DashboardUrlResolver.extractDashboardUrlFromText(
        'Open this URL: https://openclaw.local:18789/?token=Abc_123-xyz',
      );

      expect(url, 'https://openclaw.local:18789/#token=Abc_123-xyz');
    });

    test('builds dashboard url from relative redirect token', () {
      final url = DashboardUrlResolver.extractDashboardUrlFromText(
        '/#token=feedbeef',
        baseUri: Uri.parse('http://127.0.0.1:18789'),
      );

      expect(url, 'http://127.0.0.1:18789/#token=feedbeef');
    });

    test('builds dashboard url from json token body', () {
      final url = DashboardUrlResolver.extractDashboardUrlFromText(
        '{"token":"deadbeefcafebabe"}',
        baseUri: Uri.parse('http://127.0.0.1:18789'),
      );

      expect(url, 'http://127.0.0.1:18789/#token=deadbeefcafebabe');
    });

    test('detects token presence in query or fragment forms', () {
      expect(
        DashboardUrlResolver.hasToken(
          'http://127.0.0.1:18789/#token=deadbeef',
        ),
        isTrue,
      );
      expect(
        DashboardUrlResolver.hasToken(
          'https://openclaw.local:18789/?token=query-token',
        ),
        isTrue,
      );
      expect(
        DashboardUrlResolver.hasToken('http://127.0.0.1:18789'),
        isFalse,
      );
    });

    test('strips copy suffix accidentally appended after token links', () {
      final url = DashboardUrlResolver.extractDashboardUrlFromText(
        'OpenClaw: http://127.0.0.1:18789/#token=deadbeefcafecopy',
      );

      expect(url, 'http://127.0.0.1:18789/#token=deadbeefcafe');
    });

    test('strips short token copy suffix from stored dashboard url', () {
      final url = DashboardUrlResolver.normalizeDashboardUrl(
        'http://127.0.0.1:18789/#token=abcdcopy',
      );

      expect(url, 'http://127.0.0.1:18789/#token=abcd');
    });

    test('strips copied suffix accidentally appended after token links', () {
      final url = DashboardUrlResolver.extractDashboardUrlFromText(
        'OpenClaw: http://127.0.0.1:18789/#token=deadbeefcafecopied',
      );

      expect(url, 'http://127.0.0.1:18789/#token=deadbeefcafe');
    });

    test('strips GatewayWS suffix accidentally glued onto token links', () {
      final url = DashboardUrlResolver.extractDashboardUrlFromText(
        'OpenClaw: http://127.0.0.1:18789/#token=deadbeefcafeGatewayWS',
      );

      expect(url, 'http://127.0.0.1:18789/#token=deadbeefcafe');
    });

    test('normalizes stored dashboard url with GatewayWS suffix', () {
      final url = DashboardUrlResolver.normalizeDashboardUrl(
        'http://127.0.0.1:18789/#token=deadbeefcafeGatewayWS',
      );

      expect(url, 'http://127.0.0.1:18789/#token=deadbeefcafe');
    });
  });
}
