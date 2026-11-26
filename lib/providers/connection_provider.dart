/// Connection and handshake state machine.
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/ble/ble_transport.dart';
import '../core/ble/handshake.dart';
import '../core/crypto/nb_crypto.dart';
import '../core/logger.dart';
import '../core/protocol/nb_frame.dart';
import '../core/protocol/nb_protocol.dart';
import '../data/saved_device.dart';
import '../data/session_db.dart';
import 'demo_provider.dart';

/// Return [current] with bit [bit] set to [on]. Extracted so the RMW
/// math in [ConnectionNotifier.writeAndVerifyBit] is unit-testable in
/// isolation from the BLE transport.
int applyBit(int current, int bit, bool on) {
  final mask = 1 << bit;
  return on ? (current | mask) : (current & ~mask);
}

String _hex(Uint8List d, [int max = 16]) {
  final len = d.length < max ? d.length : max;
  final buf = StringBuffer();
  for (var i = 0; i < len; i++) {
    if (i > 0) buf.write(' ');
    buf.write(d[i].toRadixString(16).padLeft(2, '0'));
  }
  if (d.length > max) buf.write('...');
  return buf.toString();
}

// ---------------------------------------------------------------------------
// Connection state
// ---------------------------------------------------------------------------

enum ConnectionPhase {
  disconnected,
  connecting,
  handshaking,
  connected,
  error,
}

class BleConnectionState {
  final ConnectionPhase phase;
  final HandshakePhase? handshakePhase;
  final String? message;
  final String? deviceName;
  final String? serialNumber;
  final String? error;

  const BleConnectionState({
    this.phase = ConnectionPhase.disconnected,
    this.handshakePhase,
    this.message,
    this.deviceName,
    this.serialNumber,
    this.error,
  });

  BleConnectionState copyWith({
    ConnectionPhase? phase,
    HandshakePhase? handshakePhase,
    String? message,
    String? deviceName,
    String? serialNumber,
    String? error,
  }) =>
      BleConnectionState(
        phase: phase ?? this.phase,
        handshakePhase: handshakePhase ?? this.handshakePhase,
        message: message ?? this.message,
        deviceName: deviceName ?? this.deviceName,
        serialNumber: serialNumber ?? this.serialNumber,
        error: error,
      );

  bool get isConnected => phase == ConnectionPhase.connected;
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final connectionProvider =
    StateNotifierProvider<ConnectionNotifier, BleConnectionState>((ref) {
  if (ref.watch(demoModeProvider)) return DemoConnectionNotifier();
  return ConnectionNotifier();
});

class ConnectionNotifier extends StateNotifier<BleConnectionState> {
  ConnectionNotifier() : super(const BleConnectionState());

  BluetoothDevice? _device;
  BleTransport? _transport;
  NbCrypto? _crypto;
  ProtocolGen _gen = ProtocolGen.gen2;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;

  // Unified BLE serialization: every frame that touches the transport —
  // both reads (sendAndRecv) AND writes (sendOnly) — is enqueued on a
  // single mutex so concurrent polling timers / settings reads can never
  // interleave frames. The E125S firmware drops the link when its RX
  // buffer overflows, so we also enforce a minimum gap between ops.
  Future<void> _txChain = Future<void>.value();
  DateTime _lastTxFinished = DateTime.fromMillisecondsSinceEpoch(0);
  // Matches Segway's own dispatcher (~10 ms) — enough breathing room
  // for the device's RX buffer but small enough that a 35-register
  // snapshot doesn't add a full extra second of idle time.
  static const _minTxGap = Duration(milliseconds: 5);

  /// Enqueue [action] behind any in-flight BLE I/O. Preserves FIFO
  /// order across all callers. Each action is preceded by a throttle
  /// window so the device has a chance to recover between frames.
  Future<T> _serialize<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    final prev = _txChain;
    _txChain = prev.then((_) async {
      final since = DateTime.now().difference(_lastTxFinished);
      if (since < _minTxGap) {
        await Future.delayed(_minTxGap - since);
      }
      try {
        final result = await action();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      } finally {
        _lastTxFinished = DateTime.now();
      }
    }, onError: (_) {});
    return completer.future;
  }

  // Auto-reconnect state
  bool _userDisconnected = false;
  bool _connecting = false; // true while connect() is running
  BluetoothDevice? _lastDevice;
  String? _lastBtName;
  ProtocolGen _lastGen = ProtocolGen.gen2;
  Uint8List? _lastStoredPassword;
  Uint8List? _lastCommandIdent;
  int _reconnectAttempt = 0;
  static const _maxReconnectAttempts = 3;

  // Session reuse: cached auth+SN+counter from last successful handshake.
  // The Segway app skips PRE_COMM on reconnect and goes straight to
  // SN mode with cached session state. We do the same.
  Uint8List? _lastAuth;
  Uint8List? _lastSn;
  int? _lastCounter;
  String? _lastMac; // for saving counter on cleanup
  int _sendCount = 0; // for periodic counter save

  BleTransport? get transport => _transport;
  NbCrypto? get crypto => _crypto;
  ProtocolGen get gen => _gen;

  /// 16-byte authorization ident required as payload for cmd=0x64
  /// vehicle-action frames. Null until the user imports it from an iOS
  /// backup (see [_PasswordImportDialog] in scan_screen.dart).
  Uint8List? get commandIdent => _lastCommandIdent;

  /// Connect to a device and perform handshake.
  ///
  /// On iOS, bonded devices connect instantly but the device's BLE module
  /// may be in a stale state (echoing writes). We retry up to 5 times
  /// with escalating delays (3s→9s), disconnecting between attempts to
  /// give the device a full reset cycle.
  Future<void> connect(
    BluetoothDevice device, {
    String? btName,
    ProtocolGen gen = ProtocolGen.gen2,
    Uint8List? storedPassword,
    Uint8List? commandIdent,
  }) async {
    if (state.phase == ConnectionPhase.connecting ||
        state.phase == ConnectionPhase.handshaking) {
      return;
    }

    _userDisconnected = false;
    _reconnectAttempt = 0;
    _connecting = true; // suppress _handleDisconnect during connect
    _gen = gen;
    _lastDevice = device;
    _lastBtName = btName;
    _lastGen = gen;
    final deviceName = btName ?? device.platformName;
    talker.info('Connecting to $deviceName...');
    state = BleConnectionState(
      phase: ConnectionPhase.connecting,
      deviceName: deviceName,
      message: 'Connecting...',
    );

    // Load stored device (password + cached session state) before retry loop.
    final mac = device.remoteId.str;
    _lastMac = mac;
    final savedDevice = await SessionDatabase().getSavedDevice(mac);
    storedPassword ??= savedDevice?.password;
    commandIdent ??= savedDevice?.commandIdent;
    _lastStoredPassword = storedPassword;
    _lastCommandIdent = commandIdent;
    _lastAuth ??= savedDevice?.auth;
    _lastSn ??= savedDevice?.sn;
    _lastCounter ??= savedDevice?.counter;

    const maxAttempts = 5;
    Object? lastError;

    try {
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          final result = await _connectOnce(
            device, deviceName, gen, storedPassword, attempt, maxAttempts);

          // Cache session state for session reuse on reconnect
          _lastAuth = result.auth;
          _lastSn = result.sn;
          _lastCounter = _crypto?.counter;

          // Save device + password + session state for reconnection
          await SessionDatabase().upsertSavedDevice(SavedDevice(
            mac: mac,
            name: deviceName,
            lastConnectedMs: DateTime.now().millisecondsSinceEpoch,
            serialNumber: result.snString,
            password: result.password,
            auth: result.auth,
            sn: result.sn,
            counter: _crypto?.counter,
            commandIdent: commandIdent,
          ));

          _reconnectAttempt = 0; // Reset on successful connect
          talker.info('Connected: SN=${result.snString}');
          state = BleConnectionState(
            phase: ConnectionPhase.connected,
            deviceName: deviceName,
            serialNumber: result.snString,
            message: 'Connected',
          );
          return; // Success!

        } on HandshakeException catch (e) {
          lastError = e;
          talker.warning('Attempt $attempt/$maxAttempts failed: ${e.message}');

          // If echo detected AND we have retries left, disconnect and retry.
          // The disconnect gives the device's BLE module time to fully reset.
          if (e.message.contains('echoing') && attempt < maxAttempts) {
            state = state.copyWith(
              message: 'Reconnecting (attempt ${attempt + 1}/$maxAttempts)...',
            );
            await _cleanup();
            // Escalating delay: 3s, 5s, 7s, 9s — device firmware needs real
            // time to tear down the old session after iOS severs the link.
            final delay = Duration(seconds: 1 + attempt * 2);
            talker.info('Waiting ${delay.inSeconds}s before retry...');
            await Future.delayed(delay);
            continue;
          }
          // Non-echo error or last attempt — fall through to error state
          break;
        } catch (e) {
          lastError = e;
          talker.error('Attempt $attempt/$maxAttempts failed',
              e is Exception ? e : Exception(e.toString()));
          break; // Non-handshake errors don't retry
        }
      }

      // All attempts exhausted
      talker.error('Connection failed after $maxAttempts attempts');
      state = BleConnectionState(
        phase: ConnectionPhase.error,
        deviceName: deviceName,
        error: lastError.toString(),
      );
      await _cleanup();
    } finally {
      _connecting = false;
    }
  }

  /// Single connection + handshake attempt.
  Future<HandshakeResult> _connectOnce(
    BluetoothDevice device,
    String deviceName,
    ProtocolGen gen,
    Uint8List? storedPassword,
    int attempt,
    int maxAttempts,
  ) async {
    talker.info('=== Connection attempt $attempt/$maxAttempts ===');

    // Connect (instant for already-bonded iOS system devices).
    final sw = Stopwatch()..start();
    await device.connect(
        timeout: const Duration(seconds: 15),
        license: License.free);
    talker.debug('device.connect() completed in ${sw.elapsedMilliseconds}ms');
    _device = device;

    // Listen for disconnection
    _connectionSub?.cancel();
    _connectionSub = device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected) {
        _handleDisconnect();
      }
    });

    // Request higher MTU — matches the official Segway app which asks
    // for 250. iOS negotiates automatically to ~185; on Android we
    // must explicitly requestMtu. Some BLE stacks cap lower; log the
    // actual negotiated value so we can tell if the scooter is the
    // bottleneck.
    if (Platform.isAndroid) {
      try {
        final negotiated = await device.requestMtu(247);
        talker.info('MTU negotiated: $negotiated (asked for 247)');
      } catch (e) {
        talker.warning('MTU request failed: $e');
      }
    }
    talker.debug('MTU: ${device.mtuNow} (attempt $attempt/$maxAttempts)');

    // Discover characteristics
    state = state.copyWith(message: 'Discovering services...');
    const preferNordic = false;
    final (writeChar, notifyChar) =
        await findCharacteristics(device, preferNordic: preferNordic);

    talker.debug('Write char: ${writeChar.uuid} '
        'props=[${writeChar.properties}]');
    talker.debug('Notify char: ${notifyChar.uuid} '
        'props=[${notifyChar.properties}]');

    // Toggle CCCD off→on to reset stale notification state on bonded
    // iOS devices. The device persists CCCD from the previous session;
    // re-subscribing may jolt its protocol handler.
    talker.debug('CCCD toggle: unsubscribing...');
    try {
      await notifyChar.setNotifyValue(false);
      talker.debug('CCCD toggle: unsubscribed OK, waiting 300ms...');
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      talker.warning('CCCD unsubscribe failed (OK for first connect): $e');
    }
    await notifyChar.setNotifyValue(true);
    talker.debug('CCCD toggle: re-subscribed OK');

    // Create transport — start listening, then let stale iOS cached
    // notifications drain before activating for real communication.
    final io = FlutterBleIO(device, writeChar, notifyChar);
    _transport = BleTransport(io);
    _transport!.start();
    await Future.delayed(const Duration(milliseconds: 200));
    _transport!.activate();

    // Settling delay: give the device's protocol handler time to
    // initialize after the GATT connection is up. On iOS bonded devices,
    // connect() returns instantly but the firmware may not be ready —
    // sending PRE_COMM too early causes echo. Longer on retries.
    final settleMs = attempt > 1 ? 800 : 300;
    talker.debug('Post-activate settle: ${settleMs}ms');
    await Future.delayed(Duration(milliseconds: settleMs));

    // Create crypto context
    final ecbInput = gen == ProtocolGen.gen2 ? fwData : Uint8List(16);
    _crypto = NbCrypto(ecbInput: ecbInput);

    talker.debug('Stored password: ${storedPassword != null ? "${storedPassword.length}B" : "NONE (will SET_PWD)"}');

    // ── Session reuse: skip PRE_COMM if we have cached session state ──
    // The Segway app does this: after a successful handshake, it reconnects
    // by going straight to SN-mode register reads with the cached key.
    // The device echoes nonSN PRE_COMM when in SN mode, but accepts SN
    // frames fine. So we probe with a SN-mode read first.
    if (storedPassword != null && _lastAuth != null && _lastSn != null) {
      talker.info('Session reuse: trying SN mode with cached auth...');
      state = state.copyWith(
        phase: ConnectionPhase.handshaking,
        message: 'Resuming session...',
      );

      _crypto!.setAuthParam(_lastAuth!);
      _crypto!.setKey(storedPassword, _lastAuth!);

      // Scan counter values to find one the device accepts. On iOS,
      // bonded devices keep the HCI connection alive across app restarts,
      // so the device's SN session (and replay counter) persists. The
      // saved counter may be stale if the app was force-killed, so we
      // try progressively higher offsets. Each echoed probe is detected
      // in ~60ms, so this scan adds minimal delay.
      final saved = _lastCounter ?? 0;
      final offsets = [100, 500, 2000, 10000, 40000];
      var sessionReused = false;

      for (final offset in offsets) {
        final tryCounter = saved + offset;
        _crypto!.counter = tryCounter;

        final prevEchoCount = _transport!.echoCount;
        final probe = buildRead(boardDis, regSpeed, gen: gen);
        final probeEnc = _crypto!.encrypt(probe);
        talker.info('Session reuse: probe counter=${tryCounter + 1} '
            '(saved=$saved +$offset)');
        await _transport!.send(probeEnc);

        // Wait briefly for echo detection (~60ms typical).
        await Future.delayed(const Duration(milliseconds: 300));
        if (_transport!.echoCount > prevEchoCount) {
          talker.info('Session reuse: counter=${tryCounter + 1} echoed, '
              'trying higher');
          continue;
        }

        // Not echoed — wait for real response
        try {
          final respEnc = await _transport!.recv(
              timeout: const Duration(seconds: 2));
          final (respPlain, rc) = _crypto!.decrypt(respEnc);
          if (rc == 0) {
            final resp = parseFrame(respPlain);
            if (resp != null && resp.cmd == cmdReadResp) {
              talker.info('Session reuse OK at counter=${tryCounter + 1}!');
              sessionReused = true;
              return HandshakeResult(
                password: storedPassword,
                auth: _lastAuth!,
                sn: _lastSn!,
              );
            }
          }
          talker.warning('Session reuse: bad response (rc=$rc)');
        } on TimeoutException {
          talker.warning('Session reuse: timeout at counter=${tryCounter + 1}');
        }
        break; // non-echo failure means auth is wrong, stop scanning
      }
      if (!sessionReused) {
        talker.warning('Session reuse: all counter probes failed, '
            'falling back to full handshake');
      }

      // Session reuse failed — reset crypto for full handshake.
      // Clear cached session so we don't keep trying stale sessions.
      _lastAuth = null;
      _lastSn = null;
      _lastCounter = null;
      _crypto = NbCrypto(ecbInput: ecbInput);

      // Recreate transport to clear any stale buffered frames
      await _transport!.stop();
      final io2 = FlutterBleIO(device, writeChar, notifyChar);
      _transport = BleTransport(io2);
      _transport!.start();
      await Future.delayed(const Duration(milliseconds: 200));
      _transport!.activate();
    }

    // ── Full handshake with PRE_COMM ──
    state = state.copyWith(
      phase: ConnectionPhase.handshaking,
      message: attempt > 1
          ? 'Authenticating (attempt $attempt/$maxAttempts)...'
          : 'Authenticating...',
    );

    // Fewer PRE_COMM retries per attempt (fail fast → disconnect → wait).
    // The connection-level retry loop handles the long game.
    final preCommRetries = attempt > 1 ? 4 : 10;

    return performHandshake(
      transport: _transport!,
      crypto: _crypto!,
      btName: deviceName,
      gen: gen,
      storedPassword: storedPassword,
      preCommRetries: preCommRetries,
      onProgress: (phase, msg) {
        state = state.copyWith(
          handshakePhase: phase,
          message: msg,
        );
      },
    );
  }

  /// Disconnect.
  Future<void> disconnect() async {
    _userDisconnected = true;
    talker.info('Disconnecting...');
    await _cleanup();
    state = const BleConnectionState();
  }

  /// True while the app holds a live, authenticated session. Used by
  /// sendAndRecv / sendOnly to fail fast instead of flooding writes into
  /// a closed transport after an unexpected disconnect.
  bool get _canTalkToDevice =>
      _transport != null &&
      _crypto != null &&
      state.phase == ConnectionPhase.connected;

  /// Send a frame and receive the response.
  ///
  /// All frames (reads + writes) are enqueued on a single FIFO mutex via
  /// [_serialize] so concurrent polling timers, settings screens, and
  /// explicit user actions cannot interleave.
  Future<NbFrame?> sendAndRecv(Uint8List plaintext,
      {Duration timeout = const Duration(seconds: 5)}) {
    return _serialize<NbFrame?>(() async {
      if (!_canTalkToDevice) return null;
      final t = _transport!;
      final c = _crypto!;

      try {
        final encrypted = c.encrypt(plaintext);
        await t.send(encrypted);

        // Retry recv if we get a stale frame (e.g. PRE_COMM echo from device).
        // The device periodically re-sends old handshake frames; these fail
        // decrypt with rc != 0. Discard them and wait for the real response.
        final deadline = DateTime.now().add(timeout);
        const maxRetries = 3;
        for (var attempt = 0; attempt <= maxRetries; attempt++) {
          final remaining = deadline.difference(DateTime.now());
          if (remaining.isNegative) break;

          final respEnc = await t.recv(timeout: remaining);
          final (respPlain, rc) = c.decrypt(respEnc);
          if (rc == 0) {
            _sendCount++;
            if (_sendCount % 60 == 0) _saveCounter();
            return parseFrame(respPlain);
          }
          talker.warning(
              'sendAndRecv: decrypt failed (rc=$rc), discarding stale frame '
              '${_hex(respEnc)} — retry ${attempt + 1}/$maxRetries');
        }
        talker.warning('sendAndRecv: all retries exhausted, no valid response');
        return null;
      } on TimeoutException {
        return null;
      }
    });
  }

  /// Send a frame without waiting for response (WRITE_NR). Serialized
  /// through the same mutex as [sendAndRecv]; two writes cannot
  /// overlap, and a write cannot slip between a read's TX and RX.
  Future<void> sendOnly(Uint8List plaintext) {
    return _serialize<void>(() async {
      if (!_canTalkToDevice) return;
      final t = _transport!;
      final c = _crypto!;
      final encrypted = c.encrypt(plaintext);
      await t.send(encrypted);
    });
  }

  /// Read a register and return the frame.
  Future<NbFrame?> readRegister(int target, int register,
      {int readLen = 2, Duration timeout = const Duration(seconds: 5)}) async {
    final frame = buildRead(target, register, readLen: readLen, gen: _gen);
    return sendAndRecv(frame, timeout: timeout);
  }

  /// Read a uint16 register value.
  Future<int?> readU16(int target, int register,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final resp = await readRegister(target, register, timeout: timeout);
    if (resp != null && resp.cmd == cmdReadResp && resp.data.length >= 2) {
      return resp.readU16();
    }
    return null;
  }

  /// Read a uint32 register value.
  Future<int?> readU32(int target, int register,
      {int readLen = 4,
      Duration timeout = const Duration(seconds: 5)}) async {
    final resp =
        await readRegister(target, register, readLen: readLen, timeout: timeout);
    if (resp != null && resp.cmd == cmdReadResp && resp.data.length >= 4) {
      return resp.readU32();
    }
    return null;
  }

  /// Send raw bytes directly to the BLE characteristic, bypassing encryption.
  Future<void> sendRaw(Uint8List data) async {
    final t = _transport;
    if (t == null) return;
    talker.debug('sendRaw: ${data.length}B ${_hex(data)}');
    await t.send(data);
  }

  /// Write a register (WRITE_NR).
  Future<void> writeRegister(int target, int register, Uint8List data) async {
    final frame = buildWriteNr(target, register, data, gen: _gen);
    await sendOnly(frame);
  }

  /// Write a u16 register, then read it back to verify.
  /// Returns the actual value the device reports, or null on failure.
  Future<int?> writeAndVerifyU16(
      int target, int register, int value) async {
    final data = Uint8List(2);
    ByteData.sublistView(data).setUint16(0, value, Endian.little);
    await writeRegister(target, register, data);
    // Give the device time to process the write before reading back.
    await Future.delayed(const Duration(milliseconds: 100));
    final actual = await readU16(target, register);
    talker.debug('writeVerify: reg=0x${register.toRadixString(16)} val=$value -> actual=$actual');
    return actual;
  }

  /// Read-modify-write one bit of a u16 bitmask register, then verify.
  /// Returns the verified register value (with the bit reflected) or
  /// null if any step failed.
  Future<int?> writeAndVerifyBit(
      int target, int register, int bit, bool on) async {
    final current = await readU16(target, register);
    if (current == null) return null;
    final newValue = applyBit(current, bit, on);
    if (newValue == current) return current;
    return writeAndVerifyU16(target, register, newValue);
  }

  void _handleDisconnect() {
    // On iOS with bonded devices, connect() creates a secondary HCI
    // connection for SMP pairing (e.g. handle 0x0050) alongside the
    // pre-existing data connection (e.g. 0x004B). If the SMP connection
    // drops, flutter_blue_plus reports "disconnected" even though the
    // data connection is alive and the handshake can succeed.
    // Suppress auto-reconnect while connect() is running — the retry
    // loop there handles errors itself.
    if (_connecting) {
      talker.debug('_handleDisconnect: suppressed (connect in progress)');
      return;
    }

    talker.warning('BLE disconnected unexpectedly');

    // If we're connected and have a live transport, probe whether the
    // session is actually dead. iOS may fire spurious disconnect events
    // when non-data HCI connections drop.
    if (state.isConnected && _transport != null && _crypto != null) {
      talker.info('Session may still be alive — probing...');
      _probeSessionAlive();
      return;
    }

    _tearDownAndReconnect();
  }

  /// Send a lightweight register read to verify the session is alive.
  /// If the device responds, the disconnect was spurious — keep going.
  /// If not, tear down and auto-reconnect.
  void _probeSessionAlive() {
    readU16(boardDis, regSpeed).then((value) {
      if (!mounted) return;
      if (value != null) {
        talker.info('Session probe OK (speed=$value) — ignoring disconnect');
      } else {
        talker.warning('Session probe: no response — connection is dead');
        _tearDownAndReconnect();
      }
    }).catchError((_) {
      if (!mounted) return;
      talker.warning('Session probe failed — connection is dead');
      _tearDownAndReconnect();
    });
  }

  void _tearDownAndReconnect() {
    _cleanup();

    if (_userDisconnected || _lastDevice == null) {
      state = const BleConnectionState(
        phase: ConnectionPhase.disconnected,
        message: 'Disconnected',
      );
      return;
    }

    // Auto-reconnect
    _reconnectAttempt++;
    if (_reconnectAttempt > _maxReconnectAttempts) {
      talker.warning('Auto-reconnect: max attempts reached');
      state = const BleConnectionState(
        phase: ConnectionPhase.error,
        error: 'Connection lost. Max reconnect attempts reached.',
      );
      return;
    }

    final delay = Duration(seconds: 1 << _reconnectAttempt); // 2s, 4s, 8s
    talker.info('Auto-reconnect: attempt $_reconnectAttempt/$_maxReconnectAttempts in ${delay.inSeconds}s');
    state = BleConnectionState(
      phase: ConnectionPhase.connecting,
      deviceName: _lastBtName ?? _lastDevice!.platformName,
      message: 'Reconnecting (attempt $_reconnectAttempt/$_maxReconnectAttempts)...',
    );

    Future.delayed(delay, () {
      if (_userDisconnected || !mounted) return;
      // Don't reconnect if already connected (e.g. probe succeeded meanwhile)
      if (state.isConnected) {
        talker.debug('Auto-reconnect: already connected, skipping');
        return;
      }
      connect(
        _lastDevice!,
        btName: _lastBtName,
        gen: _lastGen,
        storedPassword: _lastStoredPassword,
      );
    });
  }

  void _saveCounter() {
    final mac = _lastMac;
    final ctr = _crypto?.counter;
    if (mac == null || ctr == null || ctr <= 0) return;
    _lastCounter = ctr;
    SessionDatabase().updateDeviceCounter(mac, ctr).catchError((e) {
      talker.warning('_saveCounter: $e');
    });
  }

  Future<void> _cleanup() async {
    talker.debug('_cleanup: stopping transport, disconnecting...');
    // Persist crypto counter before tearing down, so session reuse after
    // app restart starts at the right counter value.
    if (_lastMac != null && _crypto != null && _crypto!.counter > 0) {
      _lastCounter = _crypto!.counter;
      try {
        await SessionDatabase().updateDeviceCounter(_lastMac!, _crypto!.counter);
        talker.debug('_cleanup: saved counter=${_crypto!.counter}');
      } catch (e) {
        talker.warning('_cleanup: failed to save counter: $e');
      }
    }
    await _connectionSub?.cancel();
    _connectionSub = null;
    await _transport?.stop();
    _transport = null;
    _crypto = null;
    try {
      final sw = Stopwatch()..start();
      await _device?.disconnect();
      talker.debug('_cleanup: device.disconnect() took ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      talker.warning('_cleanup: disconnect error (ignored): $e');
    }
    _device = null;
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}
