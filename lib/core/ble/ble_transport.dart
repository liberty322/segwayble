/// BLE transport with frame reassembly and MTU fragmentation.
///
/// Port of BleTransport from segway_ble_client.py.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../logger.dart';
import '../protocol/nb_protocol.dart' show sync1, validSync2;

String _hex(Uint8List d, [int max = 0]) {
  // max=0 means "no truncation" — full hex dump. Needed so debug logs
  // contain complete BLE frames that offline tooling (`decrypt_log.py`)
  // can reconstruct without guessing the session's mKeyAuth.
  final len = (max == 0 || d.length < max) ? d.length : max;
  final buf = StringBuffer();
  for (var i = 0; i < len; i++) {
    if (i > 0) buf.write(' ');
    buf.write(d[i].toRadixString(16).padLeft(2, '0'));
  }
  if (max > 0 && d.length > max) buf.write('...');
  return buf.toString();
}

// ---------------------------------------------------------------------------
// BLE UUIDs
// ---------------------------------------------------------------------------

/// Ninebot Custom (primary — modern devices).
const nbService = '6e400001-0000-0000-006e-696e65626f74';
const nbWrite = '6e400002-0000-0000-006e-696e65626f74';
const nbNotify = '6e400004-0000-0000-006e-696e65626f74';

/// Nordic UART (compatibility fallback).
const nordicService = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const nordicWrite = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
const nordicNotify = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

// ---------------------------------------------------------------------------
// Abstract BLE I/O (for testability)
// ---------------------------------------------------------------------------

/// Abstract interface for BLE characteristic I/O.
abstract class BleIO {
  Future<void> write(Uint8List data, {bool withoutResponse = true});
  Stream<Uint8List> get notifications;
  int get mtu;
}

/// Real BLE I/O backed by flutter_blue_plus.
class FlutterBleIO implements BleIO {
  final BluetoothCharacteristic _writeChar;
  final BluetoothCharacteristic _notifyChar;
  final BluetoothDevice _device;

  FlutterBleIO(this._device, this._writeChar, this._notifyChar);

  @override
  Future<void> write(Uint8List data, {bool withoutResponse = true}) async {
    await _writeChar.write(data.toList(), withoutResponse: withoutResponse);
  }

  @override
  Stream<Uint8List> get notifications =>
      _notifyChar.onValueReceived.map((v) => Uint8List.fromList(v));

  @override
  int get mtu => _device.mtuNow;
}

// ---------------------------------------------------------------------------
// BLE Transport
// ---------------------------------------------------------------------------

/// BLE transport with frame reassembly and MTU fragmentation.
class BleTransport {
  final BleIO _io;
  final _rxBuffer = <int>[];
  final _frameQueue = <Uint8List>[];
  final _waiters = <Completer<Uint8List>>[];
  StreamSubscription<Uint8List>? _subscription;
  bool _active = false;
  Uint8List? _lastSent; // for echo detection
  int _echoCount = 0;

  BleTransport(this._io);

  /// Number of echoes detected (device reflecting writes back as notifications).
  int get echoCount => _echoCount;

  /// Start listening for notifications.
  void start() {
    _subscription = _io.notifications.listen(_onNotify);
  }

  /// Discard stale data and activate the transport for real communication.
  ///
  /// Call this after enabling notifications but before the first send.
  /// On iOS, flutter_blue_plus may deliver cached characteristic values
  /// immediately on subscribe — this clears that stale data.
  void activate() {
    _rxBuffer.clear();
    _frameQueue.clear();
    _active = true;
    talker.debug('Transport activated, stale data flushed');
  }

  /// Stop listening.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    for (final w in _waiters) {
      if (!w.isCompleted) {
        w.completeError(StateError('Transport stopped'));
      }
    }
    _waiters.clear();
  }

  void _onNotify(Uint8List data) {
    if (!_active) {
      talker.verbose('BLE notify (stale, ignored): ${data.length}B');
      return;
    }
    talker.verbose('BLE notify: ${data.length}B');
    _rxBuffer.addAll(data);
    _tryExtractFrame();
  }

  void _tryExtractFrame() {
    while (_rxBuffer.length >= 3) {
      // Find sync bytes
      var idx = -1;
      for (var i = 0; i < _rxBuffer.length - 1; i++) {
        if (_rxBuffer[i] == sync1 && validSync2.contains(_rxBuffer[i + 1])) {
          idx = i;
          break;
        }
      }
      if (idx < 0) {
        // No sync found — keep last byte if it's 0x5A
        if (_rxBuffer.isNotEmpty && _rxBuffer.last == sync1) {
          final last = _rxBuffer.last;
          _rxBuffer.clear();
          _rxBuffer.add(last);
        } else {
          _rxBuffer.clear();
        }
        return;
      }
      if (idx > 0) {
        _rxBuffer.removeRange(0, idx);
      }

      if (_rxBuffer.length < 3) return;

      final length = _rxBuffer[2];
      final total = length + 13; // encrypted frame size

      if (_rxBuffer.length < total) return; // wait for more data

      final frame = Uint8List.fromList(_rxBuffer.sublist(0, total));
      _rxBuffer.removeRange(0, total);

      // Discard echo: some devices reflect writes back as notifications.
      if (_lastSent != null && _bytesEqual(frame, _lastSent!)) {
        _echoCount++;
        talker.warning('Echo #$_echoCount: ${frame.length}B ${_hex(frame)}');
        _lastSent = null;
        continue;
      }

      talker.verbose('Frame extracted: ${frame.length}B from buffer');
      _deliverFrame(frame);
    }
  }

  void _deliverFrame(Uint8List frame) {
    // If someone is waiting, deliver immediately
    while (_waiters.isNotEmpty) {
      final w = _waiters.removeAt(0);
      if (!w.isCompleted) {
        talker.debug('BLE RX: ${frame.length}B ${_hex(frame)}');
        w.complete(frame);
        return;
      }
    }
    // Otherwise queue
    _frameQueue.add(frame);
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Send data, fragmenting at MTU boundary.
  Future<void> send(Uint8List data) async {
    _lastSent = Uint8List.fromList(data);
    talker.debug('BLE TX: ${data.length}B ${_hex(data)}');
    final mtuPayload = (_io.mtu - 3).clamp(20, 512);
    for (var offset = 0; offset < data.length; offset += mtuPayload) {
      final end = (offset + mtuPayload).clamp(0, data.length);
      final chunk = data.sublist(offset, end);
      await _io.write(chunk);
      if (end < data.length) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }
  }

  /// Wait for a complete encrypted frame.
  Future<Uint8List> recv({Duration timeout = const Duration(seconds: 5)}) async {
    // Check queue first
    if (_frameQueue.isNotEmpty) {
      final frame = _frameQueue.removeAt(0);
      talker.debug('BLE RX: ${frame.length}B ${_hex(frame)}');
      return frame;
    }

    final completer = Completer<Uint8List>();
    _waiters.add(completer);

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        _waiters.remove(completer);
        talker.warning('BLE RX timeout (${timeout.inSeconds}s)');
        completer.completeError(
          TimeoutException('No response within ${timeout.inSeconds}s'));
      }
    });

    try {
      return await completer.future;
    } finally {
      timer.cancel();
    }
  }
}

// ---------------------------------------------------------------------------
// Service discovery
// ---------------------------------------------------------------------------

/// Discover write and notify characteristics.
/// Gen2 prefers Nordic UART; Gen3 prefers Ninebot Custom.
Future<(BluetoothCharacteristic write, BluetoothCharacteristic notify)>
    findCharacteristics(BluetoothDevice device, {bool preferNordic = true}) async {
  final services = await device.discoverServices();

  // Log all discovered services and characteristics for debugging.
  for (final svc in services) {
    final chars = svc.characteristics
        .map((c) => '  ${c.uuid.str} [${c.properties}]')
        .join('\n');
    talker.debug('BLE service ${svc.uuid.str}:\n$chars');
  }

  BluetoothCharacteristic? findChar(List<BluetoothService> svcs, String uuid) {
    for (final svc in svcs) {
      for (final c in svc.characteristics) {
        if (c.uuid.str.toLowerCase() == uuid.toLowerCase()) {
          return c;
        }
      }
    }
    return null;
  }

  // Try preferred service first
  if (preferNordic) {
    final w = findChar(services, nordicWrite);
    final n = findChar(services, nordicNotify);
    if (w != null && n != null) {
      talker.info('BLE using Nordic UART');
      return (w, n);
    }

    final w2 = findChar(services, nbWrite);
    final n2 = findChar(services, nbNotify);
    if (w2 != null && n2 != null) {
      talker.info('BLE using Ninebot Custom');
      return (w2, n2);
    }
  } else {
    final w = findChar(services, nbWrite);
    final n = findChar(services, nbNotify);
    if (w != null && n != null) {
      talker.info('BLE using Ninebot Custom');
      return (w, n);
    }

    final w2 = findChar(services, nordicWrite);
    final n2 = findChar(services, nordicNotify);
    if (w2 != null && n2 != null) {
      talker.info('BLE using Nordic UART');
      return (w2, n2);
    }
  }

  // Fallback: scan for any 6e4000xx service
  for (final svc in services) {
    if (svc.uuid.str.toLowerCase().contains('6e4000')) {
      BluetoothCharacteristic? writeChar;
      BluetoothCharacteristic? notifyChar;
      for (final c in svc.characteristics) {
        if (c.properties.write || c.properties.writeWithoutResponse) {
          writeChar ??= c;
        }
        if (c.properties.notify) {
          notifyChar ??= c;
        }
      }
      if (writeChar != null && notifyChar != null) return (writeChar, notifyChar);
    }
  }

  throw StateError('No compatible BLE service found');
}
