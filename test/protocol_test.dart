import 'dart:typed_data';

import 'package:app/core/crypto/nb_crypto.dart';
import 'package:app/core/protocol/nb_frame.dart';
import 'package:app/core/protocol/nb_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Frame building', () {
    test('buildFrame produces correct header', () {
      final frame = buildFrame(boardBle, cmdPreComm, 0x00);
      expect(frame.length, 7);
      expect(frame[0], sync1); // 0x5A
      expect(frame[1], sync2Gen2); // 0xA5 for Gen2
      expect(frame[2], 0x00); // length = 0 (no data)
      expect(frame[3], btId); // 0x3E
      expect(frame[4], boardBle); // 0x04
      expect(frame[5], cmdPreComm); // 0x5B
      expect(frame[6], 0x00); // index
    });

    test('buildFrame Gen3 uses 0xB5 sync', () {
      final frame = buildFrame(boardBle, cmdPreComm, 0x00,
          gen: ProtocolGen.gen3);
      expect(frame[1], sync2Gen3); // 0xB5
    });

    test('buildFrame includes data', () {
      final data = Uint8List.fromList([0xAA, 0xBB, 0xCC]);
      final frame = buildFrame(boardDis, cmdRead, 0xB5, data: data);
      expect(frame.length, 10);
      expect(frame[2], 3); // length
      expect(frame[7], 0xAA);
      expect(frame[8], 0xBB);
      expect(frame[9], 0xCC);
    });

    test('buildFrame rejects data > 255 bytes', () {
      expect(
        () => buildFrame(boardDis, cmdRead, 0x00,
            data: Uint8List(256)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Frame parsing', () {
    test('parseFrame parses valid Gen2 response', () {
      // Device → App: [0x5A, 0xA5, LEN, board, 0x3E, cmd, index, data...]
      final data = Uint8List.fromList([
        0x5A, 0xA5, 0x02, // sync, len=2
        0x01, 0x3E, // board=DIS, btId
        0x04, 0xB5, // cmd=READ_RESP, index=0xB5
        0x64, 0x00, // data: 100 (battery %)
      ]);
      final frame = parseFrame(data);
      expect(frame, isNotNull);
      expect(frame!.boardId, 0x01);
      expect(frame.cmd, cmdReadResp);
      expect(frame.index, 0xB5);
      expect(frame.readU16(), 100);
    });

    test('parseFrame accepts Gen3 sync', () {
      final data = Uint8List.fromList([
        0x5A, 0xB5, 0x00,
        0x04, 0x3E,
        0x5B, 0x01,
      ]);
      final frame = parseFrame(data);
      expect(frame, isNotNull);
      expect(frame!.cmd, cmdPreComm);
    });

    test('parseFrame rejects invalid sync', () {
      final data = Uint8List.fromList([
        0x5A, 0xCC, 0x00,
        0x04, 0x3E,
        0x5B, 0x00,
      ]);
      expect(parseFrame(data), isNull);
    });

    test('parseFrame rejects wrong btId', () {
      final data = Uint8List.fromList([
        0x5A, 0xA5, 0x00,
        0x04, 0xFF, // wrong btId
        0x5B, 0x00,
      ]);
      expect(parseFrame(data), isNull);
    });

    test('parseFrame rejects too-short data', () {
      expect(parseFrame(Uint8List.fromList([0x5A, 0xA5])), isNull);
    });
  });

  group('NbFrame helpers', () {
    test('readU16 parses little-endian', () {
      final frame = NbFrame(
        length: 2,
        boardId: 0x01,
        cmd: 0x04,
        index: 0xB5,
        data: Uint8List.fromList([0x64, 0x00]),
      );
      expect(frame.readU16(), 100);
    });

    test('readU32 parses little-endian', () {
      final frame = NbFrame(
        length: 4,
        boardId: 0x01,
        cmd: 0x04,
        index: 0xB7,
        data: Uint8List.fromList([0xE8, 0x03, 0x00, 0x00]),
      );
      expect(frame.readU32(), 1000);
    });

    test('readAscii strips nulls', () {
      final frame = NbFrame(
        length: 14,
        boardId: 0x01,
        cmd: 0x04,
        index: 0x10,
        data: Uint8List.fromList(
            'S1DXXXXXXXXX01'.codeUnits),
      );
      expect(frame.readAscii(), 'S1DXXXXXXXXX01');
    });
  });

  group('Convenience builders', () {
    test('buildPreComm', () {
      final frame = buildPreComm();
      expect(frame[4], boardBle);
      expect(frame[5], cmdPreComm);
    });

    test('buildSetPwd with 16-byte password', () {
      final pwd = Uint8List(16);
      final frame = buildSetPwd(pwd);
      expect(frame[2], 16); // length
      expect(frame[5], cmdSetPwd);
    });

    test('buildAuth with 14-byte SN', () {
      final sn = Uint8List.fromList('S1DXXXXXXXXX01'.codeUnits);
      final frame = buildAuth(sn);
      expect(frame[2], 14);
      expect(frame[5], cmdAuth);
    });

    test('buildRead produces correct frame', () {
      final frame = buildReadBattery();
      expect(frame[4], boardDis);
      expect(frame[5], cmdRead);
      expect(frame[6], regBattery);
      expect(frame[7], 2); // read length
    });

    test('buildWriteSpeed produces correct frame', () {
      final frame = buildWriteSpeed(45);
      expect(frame[4], boardDis);
      expect(frame[5], cmdWriteNr);
      expect(frame[6], regLimitSpeed);
      // 45 in LE uint16
      expect(frame[7], 45);
      expect(frame[8], 0);
    });
  });

  group('New settings builders', () {
    test('buildReadTcs, buildReadSlope, buildReadEleBrake — MCU board', () {
      for (final builder in [
        buildReadTcs,
        buildReadSlope,
        buildReadEleBrake,
        buildReadSpeedIntensity,
        buildReadSpeedSafeLock,
      ]) {
        final frame = builder();
        expect(frame[4], boardMcu, reason: 'target');
        expect(frame[5], cmdRead, reason: 'cmd');
        expect(frame[7], 2, reason: 'read length');
      }
    });

    test('buildSetTcs/slope/eleBrake/speedIntensity/speedSafeLock — '
        'u16 WRITE_NR', () {
      final cases = <(Uint8List Function(int), int)>[
        (buildSetTcs, regTcs),
        (buildSetSlope, regSlope),
        (buildSetEleBrake, regEleBrake),
        (buildSetSpeedIntensity, regSpeedIntensity),
        (buildSetSpeedSafeLock, regSpeedSafeLock),
      ];
      for (final (builder, reg) in cases) {
        final frame = builder(2);
        expect(frame[4], boardMcu);
        expect(frame[5], cmdWriteNr);
        expect(frame[6], reg);
        expect(frame[7], 2); // LE u16 low byte
        expect(frame[8], 0);
      }
    });

    test('buildReadGearData1/2 requests 32 bytes', () {
      expect(buildReadGearData1()[7], 32);
      expect(buildReadGearData2()[7], 32);
      expect(buildReadGearData1()[6], regGearData1);
      expect(buildReadGearData2()[6], regGearData2);
    });

    test('buildReadBool2 and buildSetBool2 target DIS 0xAA', () {
      final rd = buildReadBool2();
      expect(rd[4], boardDis);
      expect(rd[5], cmdRead);
      expect(rd[6], regBool2);
      final wr = buildSetBool2(0x0010);
      expect(wr[4], boardDis);
      expect(wr[5], cmdWriteNr);
      expect(wr[6], regBool2);
      expect(wr[7], 0x10);
      expect(wr[8], 0x00);
    });

    test('buildSetAutoLock / buildReadAutoLock — DIS 0x85', () {
      expect(buildReadAutoLock()[6], regAutoLock);
      expect(buildSetAutoLock(60)[6], regAutoLock);
      expect(buildSetAutoLock(60)[7], 60);
    });

    test('buildSetAlarmVolume / buildReadAlarmVolume — DIS 0x76', () {
      expect(buildReadAlarmVolume()[6], regAlarmVolume);
      expect(buildSetAlarmVolume(42)[6], regAlarmVolume);
      expect(buildSetAlarmVolume(42)[7], 42);
    });
  });

  group('Vehicle actions', () {
    test('buildOpenAcc Gen2 targets VCU with cmd=0x64', () {
      final ident = Uint8List.fromList([0xDE, 0xAD]);
      final frame = buildOpenAcc(ident);
      expect(frame[4], boardVcu); // target = VCU (0x09)
      expect(frame[5], 0x64); // cmd = 0x64 for Gen2
      expect(frame[6], regOpenAcc);
    });

    test('buildOpenAcc Gen3 targets BLE with cmd=0x03', () {
      final ident = Uint8List.fromList([0xDE, 0xAD]);
      final frame = buildOpenAcc(ident, gen: ProtocolGen.gen3);
      expect(frame[4], boardBle); // target = BLE (0x04)
      expect(frame[5], 0x03); // cmd = 0x03 for Gen3
    });
  });

  group('Round-trip: build → encrypt → decrypt → parse', () {
    test('Non-SN round-trip', () {
      final plaintext = buildReadBattery();
      final crypto = NbCrypto(ecbInput: Uint8List.fromList(fwData));
      crypto.setKey(Uint8List.fromList('S1DXXXXXXXXX01'.codeUnits), null);

      final encrypted = crypto.encrypt(plaintext);
      final (decrypted, rc) = crypto.decrypt(encrypted);

      expect(rc, 0);
      expect(decrypted, equals(plaintext));
    });

    test('SN-mode round-trip', () {
      final auth = Uint8List.fromList(List.generate(16, (i) => i * 5));
      final plaintext = buildReadBattery();

      final encCrypto = NbCrypto();
      encCrypto.setKey(Uint8List.fromList('test'.codeUnits), auth);
      encCrypto.setAuthParam(auth);
      encCrypto.startSn();

      final encrypted = encCrypto.encrypt(plaintext);

      final decCrypto = NbCrypto();
      decCrypto.setKey(Uint8List.fromList('test'.codeUnits), auth);
      decCrypto.setAuthParam(auth);
      decCrypto.startSn();

      final (decrypted, rc) = decCrypto.decrypt(encrypted);
      expect(rc, 0);
      expect(decrypted, equals(plaintext));
    });
  });
}
