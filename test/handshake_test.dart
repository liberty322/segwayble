import 'dart:async';
import 'dart:typed_data';

import 'package:app/core/ble/ble_transport.dart';
import 'package:app/core/ble/handshake.dart';
import 'package:app/core/crypto/nb_crypto.dart';
import 'package:app/core/protocol/nb_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mock_ble_io.dart';

/// Build a Device→App frame (response format).
/// Format: [0x5A, sync2, LEN, boardFrom, 0x3E, cmd, index, data...]
/// Note: This is DIFFERENT from buildFrame() which is App→Device format.
Uint8List _buildDeviceResponse(int boardFrom, int cmd, int index,
    {Uint8List? data, ProtocolGen gen = ProtocolGen.gen2}) {
  final d = data ?? Uint8List(0);
  final cfg = protoConfig[gen]!;
  final frame = Uint8List(7 + d.length);
  frame[0] = sync1;
  frame[1] = cfg.sync2;
  frame[2] = d.length;
  frame[3] = boardFrom;
  frame[4] = btId; // 0x3E — marks it as Device→App
  frame[5] = cmd;
  frame[6] = index;
  if (d.isNotEmpty) {
    frame.setRange(7, 7 + d.length, d);
  }
  return frame;
}

/// Build a PRE_COMM response with auth(16) + SN(14) = 30 bytes data.
Uint8List _buildPreCommResponse(Uint8List auth, String sn) {
  final snBytes = Uint8List(14);
  final snCodeUnits = sn.codeUnits;
  for (var i = 0; i < snCodeUnits.length && i < 14; i++) {
    snBytes[i] = snCodeUnits[i];
  }
  final data = Uint8List.fromList([...auth, ...snBytes]);
  return _buildDeviceResponse(boardBle, cmdPreComm, 0x01, data: data);
}

/// Build an AUTH response with given index (1=success, 0=failure).
Uint8List _buildAuthResponse(int index) {
  return _buildDeviceResponse(boardBle, cmdAuth, index);
}

void main() {
  const btName = 'S1DXXXXXXXXX01';

  group('Handshake', () {
    test('stored-password reconnect skips SET_PWD phase', () async {
      final mockIO = MockBleIO();
      final transport = BleTransport(mockIO);
      transport.start();
      transport.activate();

      final auth = Uint8List.fromList(List.generate(16, (i) => i * 3));
      final storedPwd = Uint8List.fromList(List.generate(16, (i) => 0xAA));

      // The handshake will: resetSn(), setKey(btName, fwData), encrypt PRE_COMM
      // Then decrypt the response using the same crypto state.
      // We need to encrypt the response with a matching crypto context.
      final preCommCrypto = NbCrypto(ecbInput: Uint8List.fromList(fwData));
      preCommCrypto.resetSn();
      preCommCrypto.setKey(Uint8List.fromList(btName.codeUnits), fwData);
      // The handshake encrypts PRE_COMM first, advancing the non-SN state.
      // Simulate that by encrypting a dummy of same length.
      final dummyPreComm = buildPreComm(); // same as what handshake sends
      preCommCrypto.encrypt(dummyPreComm);
      // Now encrypt the response — the handshake's decrypt will match.
      final preCommResp = _buildPreCommResponse(auth, btName);
      final preCommRespEnc = preCommCrypto.encrypt(preCommResp);

      // After PRE_COMM: handshake sets authParam(auth), starts SN mode,
      // then (with stored password) skips SET_PWD and goes to AUTH.
      // Auth phase: setKey(storedPwd, auth), encrypt AUTH frame, wait for response.
      final authCrypto = NbCrypto(ecbInput: Uint8List.fromList(fwData));
      authCrypto.setKey(storedPwd, auth);
      authCrypto.setAuthParam(auth);
      authCrypto.startSn();
      // Handshake encrypts AUTH first (counter 1→2), then decrypts response.
      final dummyAuth = buildAuth(
          Uint8List.fromList(btName.codeUnits.sublist(0, 14)));
      authCrypto.encrypt(dummyAuth);
      // Encrypt the AUTH response for the handshake to decrypt.
      final authResp = _buildAuthResponse(1);
      final authRespEnc = authCrypto.encrypt(authResp);

      var responseIndex = 0;
      final responses = [preCommRespEnc, authRespEnc];
      late Timer feeder;
      feeder = Timer.periodic(const Duration(milliseconds: 50), (timer) {
        if (responseIndex >= responses.length) {
          timer.cancel();
          return;
        }
        mockIO.simulateNotify(responses[responseIndex]);
        responseIndex++;
      });

      final phases = <HandshakePhase>[];
      final crypto = NbCrypto(ecbInput: Uint8List.fromList(fwData));

      try {
        final result = await performHandshake(
          transport: transport,
          crypto: crypto,
          btName: btName,
          gen: ProtocolGen.gen2,
          storedPassword: storedPwd,
          onProgress: (phase, msg) => phases.add(phase),
        );

        expect(phases, isNot(contains(HandshakePhase.setPwd)));
        expect(phases, contains(HandshakePhase.preComm));
        expect(phases, contains(HandshakePhase.auth));
        expect(phases, contains(HandshakePhase.done));
        expect(result.password, equals(storedPwd));
        expect(result.snString, btName);
      } finally {
        feeder.cancel();
        await transport.stop();
        mockIO.dispose();
      }
    });

    test('auth rejection (index=0) throws HandshakeException', () async {
      final mockIO = MockBleIO();
      final transport = BleTransport(mockIO);
      transport.start();
      transport.activate();

      final auth = Uint8List.fromList(List.generate(16, (i) => i * 3));
      final storedPwd = Uint8List.fromList(List.generate(16, (i) => 0xBB));

      // PRE_COMM crypto (same approach as above)
      final preCommCrypto = NbCrypto(ecbInput: Uint8List.fromList(fwData));
      preCommCrypto.resetSn();
      preCommCrypto.setKey(Uint8List.fromList(btName.codeUnits), fwData);
      preCommCrypto.encrypt(buildPreComm());
      final preCommRespEnc = preCommCrypto.encrypt(
          _buildPreCommResponse(auth, btName));

      // AUTH crypto (rejection: index=0)
      final authCrypto = NbCrypto(ecbInput: Uint8List.fromList(fwData));
      authCrypto.setKey(storedPwd, auth);
      authCrypto.setAuthParam(auth);
      authCrypto.startSn();
      authCrypto.encrypt(buildAuth(
          Uint8List.fromList(btName.codeUnits.sublist(0, 14))));
      final authRespEnc = authCrypto.encrypt(_buildAuthResponse(0));

      var responseIndex = 0;
      final responses = [preCommRespEnc, authRespEnc];
      late Timer feeder;
      feeder = Timer.periodic(const Duration(milliseconds: 50), (timer) {
        if (responseIndex >= responses.length) {
          timer.cancel();
          return;
        }
        mockIO.simulateNotify(responses[responseIndex]);
        responseIndex++;
      });

      final crypto = NbCrypto(ecbInput: Uint8List.fromList(fwData));

      try {
        await expectLater(
          performHandshake(
            transport: transport,
            crypto: crypto,
            btName: btName,
            storedPassword: storedPwd,
          ),
          throwsA(isA<HandshakeException>()),
        );
      } finally {
        feeder.cancel();
        await transport.stop();
        mockIO.dispose();
      }
    });

    test('timeout when no response arrives', () async {
      final mockIO = MockBleIO();
      final transport = BleTransport(mockIO);
      transport.start();
      transport.activate();

      final crypto = NbCrypto(ecbInput: Uint8List.fromList(fwData));

      try {
        await expectLater(
          performHandshake(
            transport: transport,
            crypto: crypto,
            btName: btName,
          ),
          throwsA(isA<HandshakeException>()),
        );
      } finally {
        await transport.stop();
        mockIO.dispose();
      }
    });
  });
}
