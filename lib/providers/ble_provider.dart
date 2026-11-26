/// BLE adapter and scanning state providers.
library;

import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/ble/ble_scanner.dart';

/// BLE adapter state stream (with timeout for simulator).
final bleAdapterStateProvider = StreamProvider<BluetoothAdapterState>((ref) {
  // FlutterBluePlus.adapterState never emits on simulator.
  // Use a timeout only for the *first* event so the UI doesn't hang forever,
  // but don't re-arm after receiving a valid state (which would incorrectly
  // mark BLE as unavailable after 3 seconds of normal silence).
  var gotFirst = false;
  return FlutterBluePlus.adapterState.timeout(
    const Duration(seconds: 5),
    onTimeout: (sink) {
      if (!gotFirst) {
        sink.add(BluetoothAdapterState.unavailable);
      }
    },
  ).map((state) {
    gotFirst = true;
    return state;
  });
});

/// BLE scanner instance.
final bleScannerProvider = Provider<BleScanner>((ref) {
  final scanner = BleScanner();
  ref.onDispose(() => scanner.dispose());
  return scanner;
});

/// Whether currently scanning.
final isScanningProvider = StateProvider<bool>((ref) => false);

/// List of scanned devices.
final scannedDevicesProvider =
    StateNotifierProvider<ScannedDevicesNotifier, List<ScannedDevice>>((ref) {
  return ScannedDevicesNotifier(ref);
});

class ScannedDevicesNotifier extends StateNotifier<List<ScannedDevice>> {
  final Ref _ref;
  StreamSubscription<List<ScannedDevice>>? _sub;

  ScannedDevicesNotifier(this._ref) : super([]);

  Future<void> startScan() async {
    final scanner = _ref.read(bleScannerProvider);
    _ref.read(isScanningProvider.notifier).state = true;
    state = [];

    _sub?.cancel();
    _sub = scanner.devices.listen((devices) {
      state = devices;
    });

    await scanner.startScan();
    _ref.read(isScanningProvider.notifier).state = false;
  }

  Future<void> stopScan() async {
    final scanner = _ref.read(bleScannerProvider);
    await scanner.stopScan();
    _ref.read(isScanningProvider.notifier).state = false;
    _sub?.cancel();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
