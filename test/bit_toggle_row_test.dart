/// Widget tests for [BitToggleRow].
///
/// The async RMW call path is already covered end-to-end by the
/// virtual-scooter test; here we just exercise the presentational
/// behaviour — switch reflects bit state, disabled when register is
/// null, renders label/subtitle/icon.
library;

import 'package:app/widgets/bit_toggle_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => ProviderScope(
        child: MaterialApp(home: Scaffold(body: child)),
      );

  group('BitToggleRow', () {
    testWidgets('switch reflects the bit state', (tester) async {
      await tester.pumpWidget(wrap(const BitToggleRow(
        label: 'Push assist',
        target: 0x01,
        register: 0x7D,
        bit: 1,
        currentRegisterValue: 0x0002, // bit 1 set
      )));
      final sw = tester.widget<Switch>(find.byType(Switch));
      expect(sw.value, isTrue);
    });

    testWidgets('switch off when bit is clear', (tester) async {
      await tester.pumpWidget(wrap(const BitToggleRow(
        label: 'Reverse',
        target: 0x01,
        register: 0x7D,
        bit: 13,
        currentRegisterValue: 0x0001, // bit 13 clear
      )));
      final sw = tester.widget<Switch>(find.byType(Switch));
      expect(sw.value, isFalse);
    });

    testWidgets('switch disabled while register is unknown (null)',
        (tester) async {
      await tester.pumpWidget(wrap(const BitToggleRow(
        label: 'Parking mode',
        target: 0x01,
        register: 0x7D,
        bit: 8,
        currentRegisterValue: null,
      )));
      final sw = tester.widget<Switch>(find.byType(Switch));
      expect(sw.onChanged, isNull);
      expect(sw.value, isFalse);
    });

    testWidgets('renders label, subtitle, icon', (tester) async {
      await tester.pumpWidget(wrap(const BitToggleRow(
        label: 'Auto park',
        subtitle: 'Prevent rolling',
        icon: Icons.local_parking,
        target: 0x01,
        register: 0x7C,
        bit: 7,
        currentRegisterValue: 0,
      )));
      expect(find.text('Auto park'), findsOneWidget);
      expect(find.text('Prevent rolling'), findsOneWidget);
      expect(find.byIcon(Icons.local_parking), findsOneWidget);
    });
  });
}
