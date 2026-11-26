import 'dart:typed_data';

import 'package:app/data/credential_qr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CredentialPayload', () {
    const pwdHex = '00112233445566778899aabbccddeeff';
    const identHex = 'ffeeddccbbaa99887766554433221100';

    Uint8List hex(String h) => Uint8List.fromList([
          for (var i = 0; i < h.length; i += 2)
            int.parse(h.substring(i, i + 2), radix: 16),
        ]);

    test('parses full payload', () {
      final p = CredentialPayload.parse(
          'segway://credentials?sn=S1DCA123456789&pwd=$pwdHex&ident=$identHex')!;
      expect(p.serialNumber, 'S1DCA123456789');
      expect(p.password, hex(pwdHex));
      expect(p.commandIdent, hex(identHex));
    });

    test('parses password-only payload', () {
      final p =
          CredentialPayload.parse('segway://credentials?pwd=$pwdHex')!;
      expect(p.password, hex(pwdHex));
      expect(p.commandIdent, isNull);
      expect(p.serialNumber, isNull);
    });

    test('rejects wrong scheme or host', () {
      expect(CredentialPayload.parse('https://credentials?pwd=$pwdHex'),
          isNull);
      expect(CredentialPayload.parse('segway://other?pwd=$pwdHex'), isNull);
    });

    test('rejects bad hex lengths', () {
      expect(CredentialPayload.parse('segway://credentials?pwd=deadbeef'),
          isNull);
      expect(
          CredentialPayload.parse(
              'segway://credentials?pwd=$pwdHex&ident=xyz'),
          isNull);
    });

    test('encode round-trips through parse', () {
      final original = CredentialPayload(
        serialNumber: 'S1DCA123456789',
        password: hex(pwdHex),
        commandIdent: hex(identHex),
      );
      final parsed = CredentialPayload.parse(original.encode())!;
      expect(parsed.serialNumber, original.serialNumber);
      expect(parsed.password, original.password);
      expect(parsed.commandIdent, original.commandIdent);
    });
  });
}
