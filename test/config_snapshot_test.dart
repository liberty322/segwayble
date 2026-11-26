import 'package:app/screens/settings/config_snapshot_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatSnapshotText', () {
    test('well-formed empty snapshot', () {
      final text = formatSnapshotText(
        capturedAt: null,
        ecuPn: null,
        rawValues: const {},
        asciiValues: const {},
      );
      expect(text, startsWith('# Segway configuration snapshot\n'));
      expect(text, contains('Captured: —'));
      expect(text, isNot(contains('ECU PN:')));
      // All registers should render as placeholder "—".
      expect(text.split('—').length, greaterThan(5));
    });

    test('captures ECU PN + timestamp when provided', () {
      final ts = DateTime.utc(2026, 4, 18, 20, 0, 0);
      final text = formatSnapshotText(
        capturedAt: ts,
        ecuPn: 'FAKEECUPN12345',
        rawValues: const {},
        asciiValues: const {},
      );
      expect(text, contains('Captured: 2026-04-18T20:00:00.000Z'));
      expect(text, contains('ECU PN: FAKEECUPN12345'));
    });

    test('groups render with hex register locations', () {
      final text = formatSnapshotText(
        capturedAt: null,
        ecuPn: null,
        rawValues: const {},
        asciiValues: const {},
      );
      // Speed limit is DIS 0x01 / register 0x93
      expect(text, contains('[0x01:0x93]'));
      // TCS is MCU 0x20 / register 0x55
      expect(text, contains('[0x20:0x55]'));
      // Every group header present
      for (final title in configSnapshotGroups.keys) {
        expect(text, contains('## $title'));
      }
    });

    test('raw values are passed through formatter (km/h, hex, %)', () {
      final text = formatSnapshotText(
        capturedAt: null,
        ecuPn: null,
        rawValues: const {
          '1_147': 45, // regLimitSpeed = 0x93 = 147 → "45 km/h"
          '1_181': 87, // regBattery = 0xB5 = 181 → "87 %"
          '1_125': 0x700E, // regFunBool = 0x7D → hex + binary
        },
        asciiValues: const {},
      );
      expect(text, contains('45 km/h'));
      expect(text, contains('87 %'));
      expect(text, contains('0x700E'));
      expect(text, contains('0111000000001110')); // binary form
    });

    test('ASCII values render as quoted, nul-stripped', () {
      final text = formatSnapshotText(
        capturedAt: null,
        ecuPn: null,
        rawValues: const {},
        asciiValues: const {
          '1_16': 'S1DCA123456789\x00\x00', // regSn = 0x10 = 16
        },
      );
      expect(text, contains('"S1DCA123456789"'));
    });

    test('missing values render "—"', () {
      final text = formatSnapshotText(
        capturedAt: null,
        ecuPn: null,
        rawValues: const {},
        asciiValues: const {},
      );
      // Speed limit line should exist and end with the placeholder.
      final line = text
          .split('\n')
          .firstWhere((l) => l.contains('Speed limit'), orElse: () => '');
      expect(line, contains('—'));
    });
  });
}
