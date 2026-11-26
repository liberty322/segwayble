/// In-process virtual Segway for unit/integration tests.
///
/// Implements [BleIO] so it can plug directly into [BleTransport] /
/// [performHandshake]. Speaks the real Ninebot Gen2 Encryption2 protocol:
/// decrypts frames the app sends, updates state, and emits encrypted
/// responses through the notification stream.
///
/// Typical use:
/// ```dart
/// final scooter = VirtualScooter.defaults();
/// final transport = BleTransport(scooter)..start()..activate();
/// final result = await performHandshake(
///   transport: transport,
///   crypto: NbCrypto(ecbInput: fwData),
///   btName: scooter.btName,
///   storedPassword: scooter.storedPassword,
/// );
/// // drive further traffic through `transport` …
/// // assert with `scooter.events` / `scooter.powerOn` etc.
/// ```
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:app/core/ble/ble_transport.dart';
import 'package:app/core/crypto/nb_crypto.dart';
import 'package:app/core/protocol/nb_protocol.dart';

import 'fixtures/scooter_fixture.dart';

/// A protocol-level event observed by the scooter, for test assertions.
class ScooterEvent {
  final int target;
  final int cmd;
  final int index;
  final Uint8List data;
  final String description;

  ScooterEvent({
    required this.target,
    required this.cmd,
    required this.index,
    required this.data,
    required this.description,
  });

  @override
  String toString() => description;
}

/// Behavioural knobs for scripted tests (bad MACs, dropped responses, etc.).
class ScooterBehavior {
  /// Drop every Nth WRITE_RESP to simulate flaky device.
  final int dropWriteRespEvery;

  /// Force SET_PWD to return `index=0` (waiting for button) before
  /// acceptance. Set to false for instant accept.
  final bool requireButtonPress;

  /// If true, the scooter will not echo app writes back as notifications
  /// (which is correct behaviour). Set true to reproduce the iOS-bond
  /// echo bug that the real transport compensates for.
  final bool echoWrites;

  /// If true (real-device behaviour), READs targeting a board not listed
  /// in the fixture's [ScooterFixture.knownBoards] are silently ignored.
  /// Set false for a permissive responder that always answers with zeros.
  final bool dropUnknownBoardReads;

  /// If true (real-device behaviour), vehicle actions (cmd=0x64) whose
  /// payload does not match [ScooterFixture.commandIdent] are silently
  /// dropped. The capture confirms: the device accepts the frame (MAC
  /// verifies), but takes no action. Set false to accept any ident —
  /// useful only for debugging the crypto layer in isolation.
  final bool requireCommandIdent;

  const ScooterBehavior({
    this.dropWriteRespEvery = 0,
    this.requireButtonPress = false,
    this.echoWrites = false,
    this.dropUnknownBoardReads = true,
    this.requireCommandIdent = true,
  });
}

enum _HandshakePhase { awaitingPreComm, awaitingSetPwdOrAuth, authenticated }

/// A virtual Segway that implements [BleIO].
class VirtualScooter implements BleIO {
  final ScooterFixture fixture;
  final ScooterBehavior behavior;

  // --- Transport ---
  final _notifyController = StreamController<Uint8List>.broadcast();
  final _rxBuf = <int>[];
  @override
  final int mtu;

  // --- Crypto ---
  late final NbCrypto _crypto = NbCrypto(ecbInput: Uint8List.fromList(fwData));

  // --- Protocol state ---
  _HandshakePhase _phase = _HandshakePhase.awaitingPreComm;

  /// Password negotiated via SET_PWD (if any). Used as key1 for AUTH and
  /// all post-auth frames when the app takes the fresh-pairing path.
  Uint8List? _negotiatedPassword;

  // --- Device state (observable by tests) ---
  bool powerOn = false;
  bool seatOpen = false;
  final List<ScooterEvent> events = [];
  int writeRespCounter = 0;

  /// Vehicle-action frames with an ident that did not match
  /// [ScooterFixture.commandIdent]. Populated only when
  /// `behavior.requireCommandIdent` is true. Tests can assert on this to
  /// diagnose "why doesn't my unlock work" — if the frame shows up here
  /// instead of flipping `seatOpen`, the app is sending the wrong ident.
  final List<ScooterEvent> rejectedVehicleActions = [];

  /// READ frames targeting a board not present on this device. Populated
  /// only when `behavior.dropUnknownBoardReads` is true.
  final List<ScooterEvent> droppedReads = [];

  /// Full plaintext frames (including sync header) received from the app.
  /// Useful for fine-grained byte-level assertions.
  final List<Uint8List> receivedPlaintext = [];

  VirtualScooter({
    required this.fixture,
    this.behavior = const ScooterBehavior(),
    this.mtu = 247,
  });

  /// Convenience: build a scooter with the default E125S fixture.
  factory VirtualScooter.defaults({ScooterBehavior? behavior}) =>
      VirtualScooter(
        fixture: ScooterFixture.defaultE125s(),
        behavior: behavior ?? const ScooterBehavior(),
      );

  // Accessor shortcuts so tests stay tight.
  String get btName => fixture.btName;
  Uint8List get storedPassword => fixture.storedPassword;
  Uint8List get mKeyAuth => fixture.mKeyAuth;

  @override
  Stream<Uint8List> get notifications => _notifyController.stream;

  void dispose() {
    _notifyController.close();
  }

  // ───────────────────────────────── BleIO.write ─────────────────────────────
  //
  // Accepts MTU-sized chunks from the app, reassembles into full encrypted
  // Ninebot frames, dispatches, and emits the response (if any).

  @override
  Future<void> write(Uint8List data, {bool withoutResponse = true}) async {
    _rxBuf.addAll(data);
    while (true) {
      final frame = _tryExtractFrame();
      if (frame == null) break;

      if (behavior.echoWrites) {
        // Emit the raw frame back immediately — transport should suppress it.
        _notifyController.add(Uint8List.fromList(frame));
      }

      await _handleFrame(frame);
    }
  }

  Uint8List? _tryExtractFrame() {
    while (_rxBuf.length >= 3) {
      // Align to sync
      var idx = -1;
      for (var i = 0; i < _rxBuf.length - 1; i++) {
        if (_rxBuf[i] == sync1 && validSync2.contains(_rxBuf[i + 1])) {
          idx = i;
          break;
        }
      }
      if (idx < 0) {
        _rxBuf.clear();
        return null;
      }
      if (idx > 0) _rxBuf.removeRange(0, idx);
      if (_rxBuf.length < 3) return null;

      final length = _rxBuf[2];
      final total = length + 13;
      if (_rxBuf.length < total) return null;

      final frame = Uint8List.fromList(_rxBuf.sublist(0, total));
      _rxBuf.removeRange(0, total);
      return frame;
    }
    return null;
  }

  // ─────────────────────────── frame handling ────────────────────────────────

  Future<void> _handleFrame(Uint8List cipherframe) async {
    // Pick the right key for decrypt based on handshake phase
    _configureCryptoForIncoming(cipherframe);

    final (plain, rc) = _crypto.decrypt(cipherframe);
    if (rc != 0) {
      events.add(ScooterEvent(
        target: 0,
        cmd: 0,
        index: 0,
        data: Uint8List(0),
        description: 'BAD_DECRYPT rc=$rc frame=${_hex(cipherframe)}',
      ));
      return;
    }

    receivedPlaintext.add(plain);
    final parsed = _parseAppFrame(plain);
    if (parsed == null) {
      events.add(ScooterEvent(
        target: 0,
        cmd: 0,
        index: 0,
        data: Uint8List(0),
        description: 'UNPARSEABLE ${_hex(plain)}',
      ));
      return;
    }

    events.add(parsed);

    switch (parsed.cmd) {
      case cmdPreComm:
        await _respondPreComm();
        break;
      case cmdSetPwd:
        await _respondSetPwd(parsed);
        break;
      case cmdAuth:
        await _respondAuth(parsed);
        break;
      case cmdRead:
        if (behavior.dropUnknownBoardReads &&
            !fixture.knownBoards.contains(parsed.target)) {
          droppedReads.add(parsed);
          break;
        }
        await _respondRead(parsed);
        break;
      case cmdWrite:
        _applyWrite(parsed);
        await _respondWriteAck(parsed);
        break;
      case cmdWriteNr:
        _applyWrite(parsed);
        // WRITE_NR: no response expected
        break;
      case 0x64: // Gen2 vehicle-action WRITE_NR with $ident
        _applyVehicleAction(parsed);
        break;
      default:
        // unhandled — leave a marker
        break;
    }
  }

  // App→Device frames are formatted as:
  // [0x5A, sync2, LEN, 0x3E(btId), target, cmd, index, data...]
  ScooterEvent? _parseAppFrame(Uint8List plain) {
    if (plain.length < 7) return null;
    if (plain[0] != sync1 || !validSync2.contains(plain[1])) return null;
    if (plain[3] != btId) return null;
    final length = plain[2];
    final target = plain[4];
    final cmd = plain[5];
    final index = plain[6];
    final data = length > 0
        ? Uint8List.fromList(plain.sublist(
            7, (7 + length).clamp(7, plain.length)))
        : Uint8List(0);
    return ScooterEvent(
      target: target,
      cmd: cmd,
      index: index,
      data: data,
      description: _describe(target, cmd, index, data),
    );
  }

  // ─────────────────────────── crypto state machine ──────────────────────────

  void _configureCryptoForIncoming(Uint8List cipherframe) {
    final counter = (cipherframe[cipherframe.length - 2] << 8) |
        cipherframe[cipherframe.length - 1];
    final isNonSn = counter == 0;

    if (_phase == _HandshakePhase.awaitingPreComm && isNonSn) {
      _crypto.resetSn();
      _crypto.setKey(Uint8List.fromList(btName.codeUnits), fwData);
      return;
    }

    // In the handshake-not-yet-done and authenticated phases we might be
    // about to see SET_PWD (key=btName+auth), AUTH on fresh-pairing path
    // (key=negotiatedPwd+auth), AUTH on reconnect path (key=storedPwd+auth),
    // or any post-auth frame (key=active-session-key). Trial-decrypt with
    // each candidate and land on whichever yields a valid MAC.
    final candidates = <(Uint8List, Uint8List)>[
      if (_negotiatedPassword != null) (_negotiatedPassword!, mKeyAuth),
      (storedPassword, mKeyAuth),
      (Uint8List.fromList(btName.codeUnits), mKeyAuth),
    ];

    for (final (k1, k2) in candidates) {
      _crypto.setKey(k1, k2);
      final (_, rc) = _crypto.decrypt(cipherframe);
      if (rc == 0) return;
    }
    // None matched. Leave the last key installed so the main decrypt in
    // _handleFrame surfaces a BAD_DECRYPT event.
  }

  // ─────────────────────────── handlers ──────────────────────────────────────

  Future<void> _respondPreComm() async {
    // Build PRE_COMM_RESP: 30 bytes = auth(16) + SN(14). Index=1 signals a
    // working device; the app decides how to proceed based on whether it
    // has a stored password cached.
    final snBytes = Uint8List(14);
    final codes = fixture.serialNumber.codeUnits;
    for (var i = 0; i < codes.length && i < 14; i++) {
      snBytes[i] = codes[i];
    }
    final data = Uint8List.fromList([...mKeyAuth, ...snBytes]);
    final resp = _buildDeviceResponse(boardBle, cmdPreComm, 0x01, data: data);
    await _emitEncrypted(resp);

    _phase = _HandshakePhase.awaitingSetPwdOrAuth;
    // After PRE_COMM both sides install auth + flip to SN mode for
    // subsequent frames.
    _crypto.setAuthParam(mKeyAuth);
    _crypto.startSn();
  }

  Future<void> _respondSetPwd(ScooterEvent ev) async {
    // Bank the password the app proposed; the next AUTH frame will arrive
    // encrypted with (newPassword, auth) and we need to match.
    if (ev.data.length >= 16) {
      _negotiatedPassword = Uint8List.fromList(ev.data.sublist(0, 16));
    }

    if (behavior.requireButtonPress) {
      final waiting =
          _buildDeviceResponse(boardBle, cmdSetPwd, 0x00, data: Uint8List(0));
      await _emitEncrypted(waiting);
      Future.delayed(const Duration(milliseconds: 5), () async {
        final ok =
            _buildDeviceResponse(boardBle, cmdSetPwd, 0x01, data: Uint8List(0));
        await _emitEncrypted(ok);
      });
    } else {
      final ok =
          _buildDeviceResponse(boardBle, cmdSetPwd, 0x01, data: Uint8List(0));
      await _emitEncrypted(ok);
    }
  }

  Future<void> _respondAuth(ScooterEvent ev) async {
    // Success: index=1, no data.
    final ok =
        _buildDeviceResponse(boardBle, cmdAuth, 0x01, data: Uint8List(0));
    await _emitEncrypted(ok);
    _phase = _HandshakePhase.authenticated;
  }

  Future<void> _respondRead(ScooterEvent ev) async {
    final requestedLen = ev.data.isNotEmpty ? ev.data[0] : 2;
    final stored = fixture.registers[(ev.target, ev.index)];
    final data = stored ??
        Uint8List(requestedLen); // unknown register → zeros (still responds)
    final resp = _buildDeviceResponse(ev.target, cmdReadResp, ev.index,
        data: data);
    await _emitEncrypted(resp);
  }

  void _applyWrite(ScooterEvent ev) {
    // Stash into the register snapshot so subsequent reads reflect writes.
    fixture.registers[(ev.target, ev.index)] = Uint8List.fromList(ev.data);
  }

  Future<void> _respondWriteAck(ScooterEvent ev) async {
    writeRespCounter++;
    if (behavior.dropWriteRespEvery > 0 &&
        writeRespCounter % behavior.dropWriteRespEvery == 0) {
      return; // simulate dropped ACK
    }
    final resp = _buildDeviceResponse(ev.target, cmdWriteResp, ev.index,
        data: Uint8List(0));
    await _emitEncrypted(resp);
  }

  void _applyVehicleAction(ScooterEvent ev) {
    // Gen2: cmd=0x64 on target=0x09 (VCU). Index byte = action.
    // Real firmware checks the payload against its paired command ident;
    // frames with a wrong ident decrypt and MAC-verify fine but take no
    // effect. Model that here.
    if (behavior.requireCommandIdent) {
      if (!_bytesEqual(ev.data, fixture.commandIdent)) {
        rejectedVehicleActions.add(ev);
        return;
      }
    }

    switch (ev.index) {
      case regOpenAcc: // 0x4E
        powerOn = true;
        fixture.registers[(boardVcu, regMainPower)] = _u16(1);
        break;
      case regCloseAcc: // 0x46
        powerOn = false;
        fixture.registers[(boardVcu, regMainPower)] = _u16(0);
        break;
      case regOpenTrunk: // 0x73
        seatOpen = true;
        break;
    }
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ─────────────────────────── frame builders ────────────────────────────────

  /// Build a Device→App plaintext frame: [0x5A sync2 LEN source 0x3E cmd idx data...]
  Uint8List _buildDeviceResponse(int sourceBoard, int cmd, int index,
      {Uint8List? data, ProtocolGen gen = ProtocolGen.gen2}) {
    final d = data ?? Uint8List(0);
    final cfg = protoConfig[gen]!;
    final frame = Uint8List(7 + d.length);
    frame[0] = sync1;
    frame[1] = cfg.sync2;
    frame[2] = d.length;
    frame[3] = sourceBoard;
    frame[4] = btId;
    frame[5] = cmd;
    frame[6] = index;
    if (d.isNotEmpty) frame.setRange(7, 7 + d.length, d);
    return frame;
  }

  Future<void> _emitEncrypted(Uint8List plaintext) async {
    final enc = _crypto.encrypt(plaintext);
    // BLE notifications arrive chunked at MTU size; preserve that so the
    // reassembler in BleTransport is actually exercised.
    final payloadPer = (mtu - 3).clamp(20, 512);
    for (var off = 0; off < enc.length; off += payloadPer) {
      final end = (off + payloadPer).clamp(0, enc.length);
      _notifyController.add(Uint8List.fromList(enc.sublist(off, end)));
      if (end < enc.length) {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  // ─────────────────────────── event describer ───────────────────────────────

  String _describe(int target, int cmd, int index, Uint8List data) {
    const cmds = {
      cmdRead: 'READ',
      cmdWrite: 'WRITE',
      cmdWriteNr: 'WRITE_NR',
      cmdPreComm: 'PRE_COMM',
      cmdSetPwd: 'SET_PWD',
      cmdAuth: 'AUTH',
      0x64: 'VEH_ACTION',
    };
    final cname = cmds[cmd] ?? 'cmd0x${cmd.toRadixString(16)}';
    const boards = {
      boardDis: 'DIS',
      boardBle: 'BLE',
      boardVcu: 'VCU',
      boardMcu: 'MCU',
      boardBms1: 'BMS1',
      boardBms2: 'BMS2',
      boardHep: 'HEP',
    };
    final bname = boards[target] ?? '0x${target.toRadixString(16)}';
    final action = cmd == 0x64
        ? (index == regOpenAcc
            ? 'OPEN_ACC'
            : index == regCloseAcc
                ? 'CLOSE_ACC'
                : index == regOpenTrunk
                    ? 'OPEN_TRUNK'
                    : 'reg=0x${index.toRadixString(16)}')
        : 'reg=0x${index.toRadixString(16)}';
    return '$cname $bname $action data=${_hex(data)}';
  }

  static String _hex(Uint8List d) =>
      d.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}

Uint8List _u16(int v) {
  final b = Uint8List(2);
  ByteData.sublistView(b).setUint16(0, v, Endian.little);
  return b;
}
