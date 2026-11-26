import 'dart:typed_data';

import 'package:app/core/crypto/java_random.dart';
import 'package:app/core/crypto/nb_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Key derivation', () {
    test('derive key with btName and null key2', () {
      final key = deriveKey(
        Uint8List.fromList('S1DXXXXXXXXX01'.codeUnits),
        null,
      );
      expect(key.length, 16);
      // SHA1("S1DXXXXXXXXX01\x00\x00" + "\x00"*16)[:16]
      // Known from Python: derive_key(b"S1DXXXXXXXXX01", None)
      expect(key, isNotNull);
    });

    test('derive key with btName and FW_DATA', () {
      final key = deriveKey(
        Uint8List.fromList('S1DXXXXXXXXX01'.codeUnits),
        fwData,
      );
      expect(key.length, 16);
      // Must differ from null key2
      final nullKey = deriveKey(
        Uint8List.fromList('S1DXXXXXXXXX01'.codeUnits),
        null,
      );
      expect(key, isNot(equals(nullKey)));
    });
  });

  group('JavaRandom', () {
    test('JavaRandom(12345).nextBytes(4) matches Python output', () {
      final rng = JavaRandom(12345);
      final bytes = rng.nextBytes(4);
      // From Python: JavaRandom(12345).next_bytes(4) = 'd6209f5c'
      expect(bytes.length, 4);
      expect(bytes[0], 0xd6);
      expect(bytes[1], 0x20);
      expect(bytes[2], 0x9f);
      expect(bytes[3], 0x5c);
    });

    test('JavaRandom produces consistent output', () {
      final rng1 = JavaRandom(42);
      final rng2 = JavaRandom(42);
      expect(rng1.nextBytes(16), equals(rng2.nextBytes(16)));
    });
  });

  group('NbCrypto non-SN mode', () {
    test('Gen3 (zeros ecb_input) round-trip', () {
      final plaintext = Uint8List.fromList(
          [0x5A, 0xB5, 0x00, 0x3E, 0x04, 0x5B, 0x00]);

      final ctx1 = NbCrypto(); // default: zeros ecb_input
      ctx1.setKey(Uint8List.fromList('S1DXXXXXXXXX01'.codeUnits), null);
      final encrypted = ctx1.encrypt(plaintext);

      // Encrypted should be longer (+ 6 byte tail)
      expect(encrypted.length, plaintext.length + 6);
      // Header preserved
      expect(encrypted[0], 0x5A);
      expect(encrypted[1], 0xB5);
      expect(encrypted[2], 0x00);

      final ctx2 = NbCrypto();
      ctx2.setKey(Uint8List.fromList('S1DXXXXXXXXX01'.codeUnits), null);
      final (decrypted, rc) = ctx2.decrypt(encrypted);

      expect(rc, 0);
      expect(decrypted, equals(plaintext));
    });

    test('Gen2 (FW_DATA ecb_input) round-trip', () {
      final plaintext = Uint8List.fromList(
          [0x5A, 0xA5, 0x00, 0x3E, 0x04, 0x5B, 0x00]);

      final ctx1 = NbCrypto(ecbInput: Uint8List.fromList(fwData));
      ctx1.setKey(Uint8List.fromList('S1DXXXXXXXXX01'.codeUnits), null);
      final encrypted = ctx1.encrypt(plaintext);

      final ctx2 = NbCrypto(ecbInput: Uint8List.fromList(fwData));
      ctx2.setKey(Uint8List.fromList('S1DXXXXXXXXX01'.codeUnits), null);
      final (decrypted, rc) = ctx2.decrypt(encrypted);

      expect(rc, 0);
      expect(decrypted, equals(plaintext));
    });

    test('Gen2 and Gen3 produce different ciphertext', () {
      final plaintext = Uint8List.fromList(
          [0x5A, 0xB5, 0x00, 0x3E, 0x04, 0x5B, 0x00]);

      final ctx1 = NbCrypto(); // Gen3
      ctx1.setKey(Uint8List.fromList('S1DXXXXXXXXX01'.codeUnits), null);
      final enc1 = ctx1.encrypt(plaintext);

      final ctx2 = NbCrypto(ecbInput: Uint8List.fromList(fwData)); // Gen2
      ctx2.setKey(Uint8List.fromList('S1DXXXXXXXXX01'.codeUnits), null);
      final enc2 = ctx2.encrypt(plaintext);

      expect(enc1, isNot(equals(enc2)));
    });
  });

  group('NbCrypto SN mode', () {
    test('SN mode encrypt/decrypt round-trip', () {
      final auth = Uint8List.fromList(List.generate(16, (i) => i));
      final plaintext = Uint8List.fromList(
          [0x5A, 0xB5, 0x02, 0x3E, 0x04, 0x5C, 0x00, 0xAA, 0xBB]);

      final ctx1 = NbCrypto();
      ctx1.setKey(Uint8List.fromList('S1DXXXXXXXXX01'.codeUnits), auth);
      ctx1.setAuthParam(auth);
      ctx1.startSn();
      final encrypted = ctx1.encrypt(plaintext);

      // Encrypted: header(3) + ciphertext(6) + tag(4) + counter(2) = 15
      expect(encrypted.length, plaintext.length + 6);

      final ctx2 = NbCrypto();
      ctx2.setKey(Uint8List.fromList('S1DXXXXXXXXX01'.codeUnits), auth);
      ctx2.setAuthParam(auth);
      ctx2.startSn();
      final (decrypted, rc) = ctx2.decrypt(encrypted);

      expect(rc, 0);
      expect(decrypted, equals(plaintext));
    });

    test('SN mode counter increments', () {
      final auth = Uint8List(16);
      final plaintext = Uint8List.fromList(
          [0x5A, 0xB5, 0x00, 0x3E, 0x04, 0x5B, 0x00]);

      final ctx = NbCrypto();
      ctx.setKey(Uint8List.fromList('test'.codeUnits), auth);
      ctx.setAuthParam(auth);
      ctx.startSn();

      final enc1 = ctx.encrypt(plaintext);
      final enc2 = ctx.encrypt(plaintext);

      // Counter bytes (last 2 of encrypted frame) should differ
      expect(enc1, isNot(equals(enc2)));

      // Counter in first encrypt should be 2 (starts at 1, incremented to 2)
      expect(enc1[enc1.length - 2], 0x00);
      expect(enc1[enc1.length - 1], 0x02);

      // Counter in second encrypt should be 3
      expect(enc2[enc2.length - 2], 0x00);
      expect(enc2[enc2.length - 1], 0x03);
    });
  });

  group('Password generation', () {
    test('generatePassword produces 16 bytes', () {
      final auth = Uint8List.fromList(List.generate(16, (i) => i));
      final pwd = generatePassword(auth, timeMs: 1700000000000);
      expect(pwd.length, 16);
    });

    test('generatePassword is deterministic with fixed timeMs', () {
      final auth = Uint8List.fromList(List.generate(16, (i) => i * 17));
      final pwd1 = generatePassword(auth, timeMs: 1234567890123);
      final pwd2 = generatePassword(auth, timeMs: 1234567890123);
      expect(pwd1, equals(pwd2));
    });

    test('generatePassword differs with different timeMs', () {
      final auth = Uint8List.fromList(List.generate(16, (i) => i));
      final pwd1 = generatePassword(auth, timeMs: 1000);
      final pwd2 = generatePassword(auth, timeMs: 2000);
      expect(pwd1, isNot(equals(pwd2)));
    });
  });
}
