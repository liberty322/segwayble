import 'dart:async';
import 'dart:typed_data';

import 'package:app/core/ble/ble_transport.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mock_ble_io.dart';

/// Build a fake encrypted frame: [0x5A, 0xA5, length, ...padding to total].
/// Total = length + 13 (as BleTransport expects).
Uint8List _fakeFrame(int payloadLength) {
  final total = payloadLength + 13;
  final frame = Uint8List(total);
  frame[0] = 0x5A; // sync1
  frame[1] = 0xA5; // sync2 Gen2
  frame[2] = payloadLength;
  // Fill rest with incrementing bytes for identification
  for (var i = 3; i < total; i++) {
    frame[i] = i & 0xFF;
  }
  return frame;
}

void main() {
  late MockBleIO mockIO;
  late BleTransport transport;

  setUp(() {
    mockIO = MockBleIO();
    transport = BleTransport(mockIO);
    transport.start();
    transport.activate();
  });

  tearDown(() {
    transport.stop();
    mockIO.dispose();
  });

  group('Frame extraction', () {
    test('single-chunk frame extraction', () async {
      final frame = _fakeFrame(2); // total = 15
      mockIO.simulateNotify(frame);

      final result = await transport.recv(timeout: const Duration(seconds: 1));
      expect(result, equals(frame));
    });

    test('multi-chunk reassembly (3 notifications)', () async {
      final frame = _fakeFrame(10); // total = 23
      // Split into 3 chunks: 8 + 8 + 7
      mockIO.simulateNotify(Uint8List.fromList(frame.sublist(0, 8)));
      mockIO.simulateNotify(Uint8List.fromList(frame.sublist(8, 16)));
      mockIO.simulateNotify(Uint8List.fromList(frame.sublist(16)));

      final result = await transport.recv(timeout: const Duration(seconds: 1));
      expect(result, equals(frame));
    });

    test('garbage before sync bytes is discarded', () async {
      final frame = _fakeFrame(2);
      // Prepend 5 bytes of garbage
      final withGarbage = Uint8List.fromList([0xFF, 0xFE, 0xFD, 0xFC, 0xFB, ...frame]);
      mockIO.simulateNotify(withGarbage);

      final result = await transport.recv(timeout: const Duration(seconds: 1));
      expect(result, equals(frame));
    });

    test('multiple frames in one notification (both extracted)', () async {
      final frame1 = _fakeFrame(0); // total = 13
      final frame2 = _fakeFrame(1); // total = 14
      // Mark frame2 differently
      frame2[3] = 0xAA;

      final combined = Uint8List.fromList([...frame1, ...frame2]);
      mockIO.simulateNotify(combined);

      final result1 = await transport.recv(timeout: const Duration(seconds: 1));
      expect(result1, equals(frame1));

      final result2 = await transport.recv(timeout: const Duration(seconds: 1));
      expect(result2, equals(frame2));
    });

    test('stale data flushed on activate()', () async {
      // Send data before activate - should be ignored since we start fresh
      final staleFrame = _fakeFrame(0);

      // Create a new transport that hasn't been activated
      final io2 = MockBleIO();
      final t2 = BleTransport(io2);
      t2.start();

      // Data arrives before activate
      io2.simulateNotify(staleFrame);

      // Small delay to let the listener process
      await Future.delayed(const Duration(milliseconds: 50));

      // Now activate - should flush
      t2.activate();

      // Send a real frame after activate
      final realFrame = _fakeFrame(1);
      realFrame[3] = 0xBB; // distinguish
      io2.simulateNotify(realFrame);

      final result = await t2.recv(timeout: const Duration(seconds: 1));
      expect(result, equals(realFrame));

      await t2.stop();
      io2.dispose();
    });

    test('recv() timeout throws TimeoutException', () async {
      await expectLater(
        transport.recv(timeout: const Duration(milliseconds: 100)),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('frame size is length + 13', () async {
      // Verify that a frame with length=5 expects exactly 18 bytes total
      final frame = _fakeFrame(5);
      expect(frame.length, 18);

      mockIO.simulateNotify(frame);
      final result = await transport.recv(timeout: const Duration(seconds: 1));
      expect(result.length, 18);
    });

    test('Gen3 sync byte (0xB5) is also accepted', () async {
      final frame = _fakeFrame(0);
      frame[1] = 0xB5; // Gen3 sync2
      mockIO.simulateNotify(frame);

      final result = await transport.recv(timeout: const Duration(seconds: 1));
      expect(result[1], 0xB5);
    });
  });

  group('MTU fragmentation', () {
    test('50B frame with MTU=23 sends 3 chunks of 20+20+10', () {
      // Use fakeAsync to control time for Future.delayed in send()
      fakeAsync((async) {
        final io = MockBleIO(mtu: 23); // payload = 23-3 = 20
        final t = BleTransport(io);
        t.start();
        t.activate();

        final data = Uint8List(50);
        for (var i = 0; i < 50; i++) {
          data[i] = i;
        }

        // Start send (it uses Future.delayed internally)
        var done = false;
        t.send(data).then((_) => done = true);

        // Advance time to flush the delays
        async.elapse(const Duration(milliseconds: 100));

        expect(done, isTrue);
        expect(io.sentData.length, 3);
        expect(io.sentData[0].length, 20);
        expect(io.sentData[1].length, 20);
        expect(io.sentData[2].length, 10);

        // Verify content
        expect(io.sentData[0], equals(data.sublist(0, 20)));
        expect(io.sentData[1], equals(data.sublist(20, 40)));
        expect(io.sentData[2], equals(data.sublist(40, 50)));

        t.stop();
        io.dispose();
      });
    });

    test('frame smaller than MTU sends in one chunk', () async {
      final data = Uint8List(10);
      await transport.send(data);

      expect(mockIO.sentData.length, 1);
      expect(mockIO.sentData[0].length, 10);
    });
  });
}
