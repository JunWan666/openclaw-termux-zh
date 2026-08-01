import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/models/runtime_initialization_view.dart';
import 'package:openclaw/providers/setup_provider.dart';

void main() {
  test('display progress advances smoothly and respects stage ceiling', () {
    var progress = 0.02;
    for (var i = 0; i < 500; i++) {
      final next = RuntimeInitializationView.nextDisplayProgress(
        current: progress,
        stage: RuntimeInitializationStage.checkingDevice,
      );
      expect(next, greaterThanOrEqualTo(progress));
      expect(next, lessThanOrEqualTo(0.12));
      progress = next;
    }
    expect(progress, closeTo(0.12, 0.001));
  });

  test('completion is the only stage that immediately reaches 100 percent', () {
    expect(
      RuntimeInitializationView.nextDisplayProgress(
        current: 0.51,
        stage: RuntimeInitializationStage.configuringService,
      ),
      lessThan(0.52),
    );
    expect(
      RuntimeInitializationView.nextDisplayProgress(
        current: 0.51,
        stage: RuntimeInitializationStage.complete,
      ),
      1,
    );
  });

  test('setup logs are deduplicated, bounded, and redact secrets', () {
    final logs = <String>[];
    SetupProvider.appendSanitizedLog(
      logs,
      'Connecting?token=secret-token\napiKey: sk-1234567890abcdef',
    );
    SetupProvider.appendSanitizedLog(logs, 'apiKey: sk-1234567890abcdef');

    expect(logs, hasLength(2));
    expect(logs.join('\n'), isNot(contains('secret-token')));
    expect(logs.join('\n'), isNot(contains('1234567890abcdef')));

    for (var i = 0; i < SetupProvider.maxLogLines + 20; i++) {
      SetupProvider.appendSanitizedLog(logs, 'line $i');
    }
    expect(logs, hasLength(SetupProvider.maxLogLines));
    expect(logs.first, isNot('Connecting?token=***'));
  });
}
