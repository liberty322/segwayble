/// 3-phase Encryption2 handshake: PRE_COMM → SET_PWD → AUTH.
///
/// Port of handshake() from segway_ble_client.py.
library;

import 'dart:async' show TimeoutException;
import 'dart:typed_data';

import '../crypto/java_random.dart';
import '../crypto/nb_crypto.dart';
import '../logger.dart';
import '../protocol/nb_frame.dart' show NbFrame;
import '../protocol/nb_protocol.dart';
import 'ble_transport.dart';

/// Handshake progress phases for UI.
enum HandshakePhase {
  idle,
  preComm,
  waitingForButton,
  setPwd,
  auth,
  done,
  error,
}

/// Result of a successful handshake.
class HandshakeResult {
  final Uint8List password;
  final Uint8List auth;
  final Uint8List sn;
  final String snString;

  HandshakeResult({
    required this.password,
    required this.auth,
    required this.sn,
  }) : snString = String.fromCharCodes(sn).replaceAll('\x00', '');
}

/// Callback for handshake progress.
typedef HandshakeProgressCallback = void Function(HandshakePhase phase, String message);

/// Complete the 3-phase Encryption2 handshake.
///
/// Returns [HandshakeResult] on success, throws on failure.
Future<HandshakeResult> performHandshake({
  required BleTransport transport,
  required NbCrypto crypto,
  required String btName,
  ProtocolGen gen = ProtocolGen.gen2,
  Uint8List? storedPassword,
  HandshakeProgressCallback? onProgress,
  int preCommRetries = 10,
}) async {
  void progress(HandshakePhase phase, String msg) {
    onProgress?.call(phase, msg);
  }

  // Gen2 uses FW_DATA as initial key2; Gen3 uses null
  final initialKey2 = gen == ProtocolGen.gen2 ? fwData : null;

  // ── Phase 1: PRE_COMM (retry up to 10 times, matching original app) ──
  progress(HandshakePhase.preComm, 'Sending PRE_COMM...');

  NbFrame? resp;
  const preCommTimeout = Duration(seconds: 2);

  for (var attempt = 1; attempt <= preCommRetries; attempt++) {
    // Reset crypto state for each attempt — the original app calls
    // reset() + crypto_setKey() before every PRE_COMM send.
    crypto.resetSn();
    crypto.setKey(Uint8List.fromList(btName.codeUnits), initialKey2);

    final preCommFrame = buildPreComm(gen: gen);
    final preCommEnc = crypto.encrypt(preCommFrame);
    await transport.send(preCommEnc);

    try {
      final respEnc = await transport.recv(timeout: preCommTimeout);
      final (respPlain, _) = crypto.decrypt(respEnc);
      resp = parseFrame(respPlain);
      if (resp != null && resp.cmd == cmdPreComm && resp.data.length >= 30) {
        break; // Success
      }
      talker.warning('PRE_COMM attempt $attempt: bad response, retrying...');
      resp = null;
    } on TimeoutException {
      talker.warning('PRE_COMM attempt $attempt/$preCommRetries: timeout');
    }

    // Early abort: if device is echoing our writes, no point retrying
    if (transport.echoCount >= 3) {
      talker.warning('3+ echoes detected, aborting PRE_COMM retries early');
      break;
    }

    if (attempt < preCommRetries) {
      progress(HandshakePhase.preComm,
          'PRE_COMM retry ${attempt + 1}/$preCommRetries...');
    }
  }

  if (resp == null || resp.cmd != cmdPreComm || resp.data.length < 30) {
    // Check if the device was echoing our writes (iOS bonded device issue)
    if (transport.echoCount >= 2) {
      final e = HandshakeException(
          'Device is echoing writes instead of responding.\n\n'
          'Try: Toggle Bluetooth off/on in Control Center.\n'
          'If that fails: iOS Settings → Bluetooth → '
          'tap (i) → "Forget This Device", then re-pair.');
      talker.error('Handshake failed (echo detected)', e);
      throw e;
    }
    final e = HandshakeException(
        'PRE_COMM failed after $preCommRetries attempts');
    talker.error('Handshake failed', e);
    throw e;
  }

  final auth = Uint8List.fromList(resp.data.sublist(0, 16));
  final sn = Uint8List.fromList(resp.data.sublist(16, 30));
  final snString = String.fromCharCodes(sn).replaceAll('\x00', '');
  talker.info('Handshake: PRE_COMM -> SN=$snString');
  progress(HandshakePhase.preComm, 'Got auth + SN: $snString');

  // Set auth param and enable SN mode
  crypto.setAuthParam(auth);
  crypto.startSn();

  // Determine password
  Uint8List? password = storedPassword;

  // ── Phase 2: SET_PWD (if needed) ──
  if (password == null) {
    talker.info('Handshake: SET_PWD sent');
    progress(HandshakePhase.setPwd, 'Setting password...');
    crypto.setKey(Uint8List.fromList(btName.codeUnits), auth);

    password = generatePassword(auth);

    final setPwdFrame = buildSetPwd(password, gen: gen);
    final setPwdEnc = crypto.encrypt(setPwdFrame);
    await transport.send(setPwdEnc);

    final setPwdRespEnc =
        await transport.recv(timeout: const Duration(seconds: 10));
    final (setPwdRespPlain, setPwdRc) = crypto.decrypt(setPwdRespEnc);

    final setPwdResp = parseFrame(setPwdRespPlain);
    if (setPwdResp == null || setPwdResp.cmd != cmdSetPwd) {
      final e = HandshakeException('Invalid SET_PWD response');
      talker.error('Handshake failed', e);
      throw e;
    }

    if (setPwdResp.index == 0) {
      // Device waiting for button press
      talker.info('Handshake: waiting for button press');
      progress(HandshakePhase.waitingForButton,
          'Press the button on the vehicle...');
      final confirmEnc =
          await transport.recv(timeout: const Duration(seconds: 60));
      final (confirmPlain, confirmRc) = crypto.decrypt(confirmEnc);
      final confirmResp = parseFrame(confirmPlain);
      if (confirmResp == null || confirmResp.index != 1) {
        final e = HandshakeException('SET_PWD failed (button not pressed?)');
        talker.error('Handshake failed', e);
        throw e;
      }
    } else if (setPwdResp.index != 1) {
      final e = HandshakeException('SET_PWD rejected: index=${setPwdResp.index}');
      talker.error('Handshake failed', e);
      throw e;
    }

    talker.info('Handshake: password accepted');
    progress(HandshakePhase.setPwd, 'Password accepted');
  }

  // ��─ Phase 3: AUTH ──
  progress(HandshakePhase.auth, 'Authenticating...');
  crypto.setKey(password, auth);

  final authFrame = buildAuth(sn, gen: gen);
  final authEnc = crypto.encrypt(authFrame);
  await transport.send(authEnc);

  final authRespEnc = await transport.recv(timeout: const Duration(seconds: 5));
  final (authRespPlain, authRc) = crypto.decrypt(authRespEnc);

  final authResp = parseFrame(authRespPlain);
  if (authResp == null || authResp.cmd != cmdAuth) {
    final e = HandshakeException('Invalid AUTH response');
    talker.error('Handshake failed', e);
    throw e;
  }
  if (authResp.index != 1) {
    final e = HandshakeException('AUTH rejected: index=${authResp.index}');
    talker.error('Handshake failed', e);
    throw e;
  }

  talker.info('Handshake: AUTH -> ${authResp.index == 1 ? "OK" : "REJECTED"}');
  progress(HandshakePhase.done, 'Authenticated!');
  return HandshakeResult(password: password, auth: auth, sn: sn);
}

/// Exception during handshake.
class HandshakeException implements Exception {
  final String message;
  HandshakeException(this.message);

  @override
  String toString() => 'HandshakeException: $message';
}
