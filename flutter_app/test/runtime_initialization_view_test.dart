import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/models/runtime_initialization_view.dart';
import 'package:openclaw/models/setup_state.dart';
import 'package:openclaw/screens/runtime_welcome_screen.dart';

void main() {
  test('default initialization stages hide implementation details', () {
    for (final step in SetupStep.values) {
      final label = RuntimeInitializationView.label(
        RuntimeInitializationView.stageFor(step),
        'zh',
      );
      expect(label, isNot(contains('Ubuntu')));
      expect(label, isNot(contains('RootFS')));
      expect(label, isNot(contains('Node.js')));
      expect(label, isNot(contains('npm')));
    }
  });

  test('technical install steps map to generic core deployment', () {
    for (final step in const [
      SetupStep.extractingRootfs,
      SetupStep.installingNode,
      SetupStep.installingOpenClaw,
    ]) {
      expect(
        RuntimeInitializationView.stageFor(step),
        RuntimeInitializationStage.deployingCore,
      );
    }
  });

  testWidgets('first-run welcome requires explicit agreement', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        home: RuntimeWelcomeScreen(),
      ),
    );

    expect(find.text('Welcome to OpenClaw'), findsOneWidget);
    expect(find.textContaining('OpenClaw 2026.3.23'), findsOneWidget);
    final continueButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Agree and continue'),
    );
    expect(continueButton.onPressed, isNull);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    final enabledButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Agree and continue'),
    );
    expect(enabledButton.onPressed, isNotNull);
  });
}
