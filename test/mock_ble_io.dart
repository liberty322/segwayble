import 'dart:async';
import 'dart:typed_data';

import 'package:app/core/ble/ble_transport.dart';

/// Mock BLE I/O for testing BleTransport without real Bluetooth.
class MockBleIO implements BleIO {
  final _controller = StreamController<Uint8List>.broadcast();
  final List<Uint8List> sentData = [];
  final int _mtu;

  MockBleIO({int mtu = 512}) : _mtu = mtu;

  @override
  Future<void> write(Uint8List data, {bool withoutResponse = true}) async {
    sentData.add(Uint8List.fromList(data));
  }

  @override
  Stream<Uint8List> get notifications => _controller.stream;

  @override
  int get mtu => _mtu;

  /// Simulate a notification from the BLE device.
  void simulateNotify(Uint8List data) {
    _controller.add(data);
  }

  void dispose() {
    _controller.close();
  }
}
