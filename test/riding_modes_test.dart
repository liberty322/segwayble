import 'package:app/screens/settings/riding_modes_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RidingMode modeById(String id) =>
      ridingModes.firstWhere((m) => m.id == id);

  group('activeRidingMode()', () {
    test('null mask → null', () {
      expect(activeRidingMode(null), isNull);
    });

    test('zero mask → null', () {
      expect(activeRidingMode(0), isNull);
    });

    test('unknown-only bits → null', () {
      // bits 5..15 are not in ridingModes.
      expect(activeRidingMode(0x8020), isNull);
    });

    test('ECO bit (0) picks ECO', () {
      expect(activeRidingMode(0x0001)?.id, 'eco');
    });

    test('Coast bit (1) picks Coast', () {
      expect(activeRidingMode(0x0002)?.id, 'coast');
    });

    test('Furious bit (2) picks Furious', () {
      expect(activeRidingMode(0x0004)?.id, 'furious');
    });

    test('Custom M1 bit (3) picks M1', () {
      expect(activeRidingMode(0x0008)?.id, 'm1');
    });

    test('Custom M2 bit (4) picks M2', () {
      expect(activeRidingMode(0x0010)?.id, 'm2');
    });

    test('multi-mode: first in ridingModes order wins', () {
      // ECO (bit 0) and M1 (bit 3) both set → ECO wins because it's
      // earlier in the list.
      expect(activeRidingMode(0x0009)?.id, 'eco');
    });

    test('preserves unknown higher bits (ignored for detection)', () {
      final hi = 0x8000 | (1 << 2); // unknown bit + Furious
      expect(activeRidingMode(hi)?.id, 'furious');
    });
  });

  group('rBool2ForMode()', () {
    test('clears all known bits and sets only the new mode', () {
      // Start with ECO (0x01) + Coast (0x02) both set.
      final newMask = rBool2ForMode(0x0003, modeById('furious'));
      // bit 2 = 0x04 — no other mode bits should remain.
      expect(newMask, 0x0004);
    });

    test('preserves unknown high bits', () {
      final newMask =
          rBool2ForMode(0x8008 /* M1 + unknown */, modeById('eco'));
      // 0x8000 preserved, M1 cleared, ECO set.
      expect(newMask, 0x8001);
    });

    test('from null current → just the selected mode', () {
      expect(rBool2ForMode(null, modeById('m2')), 0x0010);
    });

    test('selecting same mode is idempotent', () {
      final m1 = modeById('m1');
      expect(rBool2ForMode(m1.mask, m1), m1.mask);
    });
  });
}
