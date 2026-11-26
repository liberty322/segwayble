import 'dart:typed_data';

import 'package:app/data/saved_device.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SavedDevice serialization', () {
    test('round-trips commandIdent through toMap/fromMap', () {
      final ident = Uint8List.fromList(List.generate(16, (i) => i * 0x11));
      final pwd = Uint8List.fromList(List.generate(16, (i) => 0xA0 + i));

      final dev = SavedDevice(
        mac: 'AA:BB:CC:DD:EE:FF',
        name: 'S1DCA123456789',
        lastConnectedMs: 1700000000000,
        serialNumber: 'S1DCA123456789',
        password: pwd,
        commandIdent: ident,
      );

      final map = dev.toMap();
      expect(map['command_ident'], isA<String>()); // base64
      final restored = SavedDevice.fromMap(map);
      expect(restored.commandIdent, ident);
      expect(restored.password, pwd);
      expect(restored.mac, dev.mac);
    });

    test('null commandIdent survives round-trip as null', () {
      final dev = SavedDevice(
        mac: 'AA:BB:CC:DD:EE:FF',
        name: 'test',
        lastConnectedMs: 0,
      );
      expect(SavedDevice.fromMap(dev.toMap()).commandIdent, isNull);
    });

    test('copyWith replaces commandIdent', () {
      final initial = SavedDevice(
        mac: 'x',
        name: 'y',
        lastConnectedMs: 0,
        commandIdent: Uint8List.fromList(List.filled(16, 0x01)),
      );
      final newIdent = Uint8List.fromList(List.filled(16, 0x02));
      final updated = initial.copyWith(commandIdent: newIdent);
      expect(updated.commandIdent, newIdent);
      expect(initial.commandIdent, isNot(newIdent));
    });
  });
}
