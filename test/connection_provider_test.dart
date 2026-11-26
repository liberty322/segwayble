/// Pure-logic tests for connection_provider helpers. The BLE-dependent
/// paths (writeAndVerifyU16 round-trip, handshake retry) are covered by
/// virtual_scooter_test.dart end-to-end.
library;

import 'package:app/providers/connection_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('applyBit', () {
    test('sets a cleared bit', () {
      expect(applyBit(0x0000, 3, true), 0x0008);
    });

    test('clears a set bit', () {
      expect(applyBit(0xFFFF, 0, false), 0xFFFE);
    });

    test('preserves other bits', () {
      expect(applyBit(0xA5A5, 4, true), 0xA5B5);
      expect(applyBit(0xA5A5, 7, false), 0xA525);
    });

    test('idempotent when bit already in target state', () {
      expect(applyBit(0x0010, 4, true), 0x0010);
      expect(applyBit(0x0000, 4, false), 0x0000);
    });

    test('handles top bit (bit 15)', () {
      expect(applyBit(0x0000, 15, true), 0x8000);
      expect(applyBit(0x8000, 15, false), 0x0000);
    });
  });
}
