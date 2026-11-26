/// End-to-end tests against the in-process [VirtualScooter] emulator.
///
/// These exercise the real [BleTransport], [NbCrypto] and [performHandshake]
/// code paths against a device that speaks the full Ninebot Gen2 protocol.
library;

import 'dart:typed_data';

import 'package:app/core/ble/ble_transport.dart';
import 'package:app/core/ble/handshake.dart';
import 'package:app/core/crypto/nb_crypto.dart';
import 'package:app/core/protocol/nb_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/scooter_fixture.dart';
import 'virtual_scooter.dart';

/// Runs the full 3-phase handshake against [scooter] and returns the result.
Future<(BleTransport, HandshakeResult, NbCrypto)> _connect(
    VirtualScooter scooter,
    {Uint8List? storedPassword}) async {
  final transport = BleTransport(scooter);
  transport.start();
  transport.activate();

  final crypto = NbCrypto(ecbInput: Uint8List.fromList(fwData));
  final result = await performHandshake(
    transport: transport,
    crypto: crypto,
    btName: scooter.btName,
    storedPassword: storedPassword ?? scooter.storedPassword,
  );
  return (transport, result, crypto);
}

/// One encrypt + send, matching how connection_provider.sendOnly() works.
Future<void> _sendOnly(
    BleTransport transport, NbCrypto crypto, Uint8List plain) async {
  await transport.send(crypto.encrypt(plain));
}

/// Encrypt, send, and wait for one decrypted response.
Future<(Uint8List plain, int rc)> _sendAndRecv(
    BleTransport transport, NbCrypto crypto, Uint8List plain,
    {Duration timeout = const Duration(seconds: 2)}) async {
  await transport.send(crypto.encrypt(plain));
  final enc = await transport.recv(timeout: timeout);
  return crypto.decrypt(enc);
}

void main() {
  group('VirtualScooter handshake', () {
    test('stored-password reconnect completes PRE_COMM → AUTH', () async {
      final scooter = VirtualScooter.defaults();
      try {
        final (transport, result, _) = await _connect(scooter);

        expect(result.snString, scooter.btName);
        expect(result.auth, scooter.mKeyAuth);
        expect(result.password, scooter.storedPassword);
        expect(scooter.events.map((e) => e.cmd),
            containsAllInOrder([cmdPreComm, cmdAuth]));
        expect(scooter.events.map((e) => e.cmd), isNot(contains(cmdSetPwd)));

        await transport.stop();
      } finally {
        scooter.dispose();
      }
    });

    test('fresh-pairing SET_PWD path completes all three phases', () async {
      final scooter = VirtualScooter.defaults();
      try {
        final transport = BleTransport(scooter);
        transport.start();
        transport.activate();

        final crypto = NbCrypto(ecbInput: Uint8List.fromList(fwData));
        final result = await performHandshake(
          transport: transport,
          crypto: crypto,
          btName: scooter.btName,
          // No stored password → app will run SET_PWD.
        );

        expect(result.snString, scooter.btName);
        // App generated a fresh 16-byte password, different from the stored one.
        expect(result.password.length, 16);
        expect(scooter.events.map((e) => e.cmd),
            containsAllInOrder([cmdPreComm, cmdSetPwd, cmdAuth]));

        await transport.stop();
      } finally {
        scooter.dispose();
      }
    });
  });

  group('VirtualScooter writes after handshake', () {
    test('openTrunk with correct command ident flips seatOpen', () async {
      final scooter = VirtualScooter.defaults();
      try {
        final (transport, _, crypto) = await _connect(scooter);

        expect(scooter.seatOpen, isFalse);

        final frame = buildFrame(
          protoConfig[ProtocolGen.gen2]!.vehicleTarget,
          protoConfig[ProtocolGen.gen2]!.vehicleCmd,
          regOpenTrunk,
          data: scooter.fixture.commandIdent,
        );
        await _sendOnly(transport, crypto, frame);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(scooter.seatOpen, isTrue);
        expect(scooter.rejectedVehicleActions, isEmpty);
        await transport.stop();
      } finally {
        scooter.dispose();
      }
    });

    test('openTrunk with ecuPn-as-ident (current app behaviour) is REJECTED',
        () async {
      // This is exactly what lib/screens/dashboard_screen.dart builds today:
      // it hands utf8(ecuPn) as the ident. The real device silently ignores
      // the command because the payload does not match its paired
      // command ident. This test is the regression guard — if it starts passing
      // (seatOpen becomes true), the app has been fixed.
      final scooter = VirtualScooter.defaults();
      try {
        final (transport, _, crypto) = await _connect(scooter);

        final wrongIdent = Uint8List.fromList(scooter.fixture.ecuPn.codeUnits);
        final frame = buildFrame(
            boardVcu, 0x64, regOpenTrunk, data: wrongIdent);
        await _sendOnly(transport, crypto, frame);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(scooter.seatOpen, isFalse,
            reason: 'wrong ident must NOT open the seat');
        expect(scooter.rejectedVehicleActions, hasLength(1));
        expect(scooter.rejectedVehicleActions.first.data, wrongIdent);

        await transport.stop();
      } finally {
        scooter.dispose();
      }
    });

    test('openAcc then closeAcc toggles powerOn and rMainPower', () async {
      final scooter = VirtualScooter.defaults();
      try {
        final (transport, _, crypto) = await _connect(scooter);

        final ident = scooter.fixture.commandIdent;

        await _sendOnly(transport, crypto,
            buildFrame(boardVcu, 0x64, regOpenAcc, data: ident));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(scooter.powerOn, isTrue);

        final (resp, rc) =
            await _sendAndRecv(transport, crypto, buildReadMainPower());
        expect(rc, 0);
        expect(parseFrame(resp)!.readU16(), 1);

        await _sendOnly(transport, crypto,
            buildFrame(boardVcu, 0x64, regCloseAcc, data: ident));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(scooter.powerOn, isFalse);

        final (resp2, rc2) =
            await _sendAndRecv(transport, crypto, buildReadMainPower());
        expect(rc2, 0);
        expect(parseFrame(resp2)!.readU16(), 0);

        await transport.stop();
      } finally {
        scooter.dispose();
      }
    });

    test('READ to unknown board is silently dropped (real-device behaviour)',
        () async {
      final scooter = VirtualScooter.defaults();
      try {
        final (transport, _, crypto) = await _connect(scooter);

        // Board 0x00 / 0x07 are not wired on E125S. In the fail-switch
        // capture the real device sends no response for these — our app
        // times out its READ and moves on.
        final req = buildRead(0x07, 0x10, readLen: 14);
        await transport.send(crypto.encrypt(req));
        // Wait a beat so the emulator had time to NOT respond.
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(scooter.droppedReads, hasLength(1));
        expect(scooter.droppedReads.first.target, 0x07);

        await transport.stop();
      } finally {
        scooter.dispose();
      }
    });

    test('battery READ returns the fixture value', () async {
      final scooter = VirtualScooter.defaults();
      try {
        final (transport, _, crypto) = await _connect(scooter);

        final (plain, rc) =
            await _sendAndRecv(transport, crypto, buildReadBattery());
        expect(rc, 0);
        final frame = parseFrame(plain)!;
        expect(frame.cmd, cmdReadResp);
        expect(frame.index, regBattery);
        expect(frame.readU16(), 87);

        await transport.stop();
      } finally {
        scooter.dispose();
      }
    });

    test('new MCU setters (TCS/slope/eleBrake) roundtrip correctly',
        () async {
      final scooter = VirtualScooter.defaults();
      try {
        final (transport, _, crypto) = await _connect(scooter);

        Future<void> writeU16(Uint8List frame) async {
          await transport.send(crypto.encrypt(frame));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }

        Future<int> readU16(Uint8List frame) async {
          await transport.send(crypto.encrypt(frame));
          final (plain, rc) = crypto.decrypt(await transport.recv());
          expect(rc, 0);
          return parseFrame(plain)!.readU16();
        }

        // TCS 0 -> 2
        await writeU16(buildSetTcs(2));
        expect(await readU16(buildReadTcs()), 2);
        // Slope 0 -> 1
        await writeU16(buildSetSlope(1));
        expect(await readU16(buildReadSlope()), 1);
        // EleBrake 0 -> 1
        await writeU16(buildSetEleBrake(1));
        expect(await readU16(buildReadEleBrake()), 1);

        await transport.stop();
      } finally {
        scooter.dispose();
      }
    });

    test('writeAndVerifyBit flips a single bit without clobbering others',
        () async {
      final scooter = VirtualScooter.defaults();
      try {
        final (transport, _, crypto) = await _connect(scooter);

        // Pre-seed FunBool to 0b1010 (bits 1 and 3 set).
        final seed = Uint8List(2);
        ByteData.sublistView(seed).setUint16(0, 0x000A, Endian.little);
        await transport.send(crypto.encrypt(
            buildFrame(boardDis, cmdWrite, regFunBool, data: seed)));
        await transport.recv(); // swallow WRITE_RESP

        // Read current, set bit 0, write, verify bit 0 ON, others preserved.
        await transport.send(crypto.encrypt(buildRead(boardDis, regFunBool)));
        final (plain, rc) = crypto.decrypt(await transport.recv());
        expect(rc, 0);
        final current = parseFrame(plain)!.readU16();
        expect(current, 0x000A);

        final flipped = current | (1 << 0);
        final w = Uint8List(2);
        ByteData.sublistView(w).setUint16(0, flipped, Endian.little);
        await transport.send(crypto.encrypt(
            buildFrame(boardDis, cmdWrite, regFunBool, data: w)));
        await transport.recv();

        await transport.send(crypto.encrypt(buildRead(boardDis, regFunBool)));
        final (plain2, rc2) = crypto.decrypt(await transport.recv());
        expect(rc2, 0);
        expect(parseFrame(plain2)!.readU16(), 0x000B);

        await transport.stop();
      } finally {
        scooter.dispose();
      }
    });

    test('rBool2 riding-mode mask writes and reads back', () async {
      final scooter = VirtualScooter.defaults();
      try {
        final (transport, _, crypto) = await _connect(scooter);

        // Select Custom M1 (bit 4 = mask 0x10).
        await transport.send(crypto.encrypt(buildSetBool2(0x10)));
        await Future<void>.delayed(const Duration(milliseconds: 10));

        await transport.send(crypto.encrypt(buildReadBool2()));
        final (plain, rc) = crypto.decrypt(await transport.recv());
        expect(rc, 0);
        expect(parseFrame(plain)!.readU16(), 0x10);

        await transport.stop();
      } finally {
        scooter.dispose();
      }
    });

    test('WRITE (cmd=0x02) gets a WRITE_RESP ACK and persists', () async {
      final scooter = VirtualScooter.defaults();
      try {
        final (transport, _, crypto) = await _connect(scooter);

        // Write a new speed limit and verify via read-back.
        final newLimit = Uint8List(2);
        ByteData.sublistView(newLimit).setUint16(0, 200, Endian.little);

        // Use WRITE (0x02) instead of WRITE_NR so we get an ACK to verify
        // the full request/response round-trip.
        final writeFrame = buildFrame(boardDis, cmdWrite, regLimitSpeed,
            data: newLimit);
        final (ack, rc) = await _sendAndRecv(transport, crypto, writeFrame);
        expect(rc, 0);
        expect(parseFrame(ack)!.cmd, cmdWriteResp);

        final (plain, rc2) =
            await _sendAndRecv(transport, crypto, buildReadSpeedLimit());
        expect(rc2, 0);
        expect(parseFrame(plain)!.readU16(), 200);

        await transport.stop();
      } finally {
        scooter.dispose();
      }
    });
  });

  group('VirtualScooter edge cases', () {
    test('echoed writes from device are suppressed by transport', () async {
      final scooter = VirtualScooter(
        fixture: ScooterFixture.defaultE125s(),
        behavior: const ScooterBehavior(echoWrites: true),
      );
      try {
        final (transport, _, _) = await _connect(scooter);

        // Echo suppression is the whole mechanism here — if this completes
        // the handshake worked despite every write being reflected as a
        // notification.
        expect(transport.echoCount, greaterThan(0));
        await transport.stop();
      } finally {
        scooter.dispose();
      }
    });
  });
}

/// Short alias for test readability.
String get ecuPn => '146DU0001V1.0';
