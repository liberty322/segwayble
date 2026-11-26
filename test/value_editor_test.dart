import 'package:app/widgets/value_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  group('ValueEditor', () {
    testWidgets('Save button disabled when pending equals current',
        (tester) async {
      await tester.pumpWidget(wrap(ValueEditor(
        title: 'Speed limit',
        current: 25,
        min: 0,
        max: 100,
        step: 5,
        format: (v) => '$v km/h',
        onSave: (_) async => 25,
      )));
      final saveBtn = tester.widget<ElevatedButton>(find
          .widgetWithText(ElevatedButton, 'Save'));
      expect(saveBtn.onPressed, isNull);
    });

    testWidgets('+ stepper enables Save and writes new value',
        (tester) async {
      int? writtenValue;
      await tester.pumpWidget(wrap(ValueEditor(
        title: 'Speed limit',
        current: 25,
        min: 0,
        max: 100,
        step: 5,
        format: (v) => '$v km/h',
        onSave: (v) async {
          writtenValue = v;
          return v; // device accepts
        },
      )));

      // Tap the + button (there are 2 stepper buttons; index 1 is "+")
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      final saveBtn = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Save'));
      expect(saveBtn.onPressed, isNotNull);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(writtenValue, 30);
    });

    testWidgets('Clamped device return value shows snackbar', (tester) async {
      await tester.pumpWidget(wrap(ValueEditor(
        title: 'Speed limit',
        current: 25,
        min: 0,
        max: 100,
        step: 5,
        format: (v) => '$v km/h',
        onSave: (_) async => 20, // device clamps down
      )));

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Device clamped'), findsOneWidget);
    });

    testWidgets('- stepper disabled at min; + disabled at max', (tester) async {
      await tester.pumpWidget(wrap(ValueEditor(
        title: 'X',
        current: 0,
        min: 0,
        max: 5,
        step: 1,
        format: (v) => '$v',
        onSave: (_) async => 0,
      )));
      final minusBtn = tester.widget<IconButton>(find
          .ancestor(
              of: find.byIcon(Icons.remove), matching: find.byType(IconButton))
          .first);
      expect(minusBtn.onPressed, isNull);

      // Tap + five times to reach max
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();
      }
      final plusBtn = tester.widget<IconButton>(find
          .ancestor(
              of: find.byIcon(Icons.add), matching: find.byType(IconButton))
          .first);
      expect(plusBtn.onPressed, isNull);
    });
  });
}
