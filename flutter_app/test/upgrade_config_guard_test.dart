import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/services/upgrade_config_guard.dart';

void main() {
  test('迁移补充默认字段但不覆盖已有 Provider、Token 和 Base URL', () {
    final original = <String, dynamic>{
      'gateway': {
        'auth': {'token': 'user-token'},
      },
      'models': {
        'providers': {
          'custom': {
            'baseUrl': 'https://example.com/custom',
            'apiKey': 'secret-key',
          },
        },
      },
      'unknownFutureField': {'enabled': true},
    };
    final migrated = <String, dynamic>{
      'gateway': {
        'auth': {'token': 'generated-token', 'mode': 'token'},
        'bind': 'loopback',
      },
      'models': {
        'providers': {
          'custom': {
            'baseUrl': 'https://example.com/v1',
            'apiKey': 'replacement',
            'type': 'openai-compatible',
          },
        },
      },
      'newDefault': true,
    };

    final merged = UpgradeConfigGuard.mergePreservingUserValues(
      original,
      migrated,
    );

    expect(merged['gateway']['auth']['token'], 'user-token');
    expect(merged['gateway']['auth']['mode'], 'token');
    expect(merged['gateway']['bind'], 'loopback');
    expect(
      merged['models']['providers']['custom']['baseUrl'],
      'https://example.com/custom',
    );
    expect(merged['models']['providers']['custom']['apiKey'], 'secret-key');
    expect(
        merged['models']['providers']['custom']['type'], 'openai-compatible');
    expect(merged['unknownFutureField'], {'enabled': true});
    expect(merged['newDefault'], isTrue);
  });

  test('空旧值允许新版默认值生效', () {
    final merged = UpgradeConfigGuard.mergePreservingUserValues(
      {
        'gateway': {'bind': ''}
      },
      {
        'gateway': {'bind': 'loopback'}
      },
    );
    expect(merged['gateway']['bind'], 'loopback');
  });

  test('用户数组保持原序和内容，空数组允许迁移默认值生效', () {
    final originalProviders = ['custom-b', 'custom-a'];
    final merged = UpgradeConfigGuard.mergePreservingUserValues(
      {
        'providers': originalProviders,
        'fallbacks': <String>[],
      },
      {
        'providers': ['default'],
        'fallbacks': ['stable'],
      },
    );

    expect(merged['providers'], ['custom-b', 'custom-a']);
    expect(merged['fallbacks'], ['stable']);
    expect(originalProviders, ['custom-b', 'custom-a']);
  });

  test('顶层非对象配置拒绝迁移且空配置安全解码', () {
    expect(UpgradeConfigGuard.decodeObject(null), isEmpty);
    expect(UpgradeConfigGuard.decodeObject('  '), isEmpty);
    expect(
      () => UpgradeConfigGuard.decodeObject('["invalid"]'),
      throwsFormatException,
    );
  });

  test('结构化差异不泄露 Token、Secret 和 API Key', () {
    final changes = UpgradeConfigGuard.describeChanges(
      {
        'gateway': {'token': 'old-token'},
        'provider': {'apiKey': 'old-key'},
      },
      {
        'gateway': {'token': 'new-token'},
        'provider': {'apiKey': 'new-key'},
        'feature': true,
      },
    );
    final text =
        changes.map((change) => '${change.path}:${change.summary}').join('\n');
    expect(text, isNot(contains('old-token')));
    expect(text, isNot(contains('new-token')));
    expect(text, isNot(contains('old-key')));
    expect(text, isNot(contains('new-key')));
    expect(text, contains('[已隐藏敏感值]'));
  });

  test('新增和删除的敏感字段同样只记录隐藏摘要', () {
    final changes = UpgradeConfigGuard.describeChanges(
      {
        'auth': {'secretRef': 'old-secret-ref'},
        'unknownOld': true,
      },
      {
        'auth': {'privateKey': 'new-private-key'},
        'unknownNew': {'enabled': true},
      },
    );
    final text = changes
        .map((change) => '${change.kind}:${change.path}:${change.summary}')
        .join('\n');

    expect(text, contains('removed:auth.secretRef:[已隐藏敏感值]'));
    expect(text, contains('added:auth.privateKey:[已隐藏敏感值]'));
    expect(text, isNot(contains('old-secret-ref')));
    expect(text, isNot(contains('new-private-key')));
    expect(text, contains('removed:unknownOld'));
    expect(text, contains('added:unknownNew'));
  });
}
