/// BLE device scanner with Segway/Ninebot filtering.
library;

import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_transport.dart' show nbService, nordicService;

/// Scanned BLE device with metadata.
class ScannedDevice {
  final BluetoothDevice device;
  final String name;
  final int rssi;
  final bool isSegway;
  final bool isSystemDevice;

  const ScannedDevice({
    required this.device,
    required this.name,
    required this.rssi,
    required this.isSegway,
    this.isSystemDevice = false,
  });

  String get id => device.remoteId.str;
}

/// Check if a BLE name looks like a Segway/Ninebot device.
bool isSegwayName(String name) {
  final upper = name.toUpperCase();
  return upper.startsWith('S1D') ||
      upper.startsWith('NB-') ||
      upper.contains('NINEBOT') ||
      upper.contains('SEGWAY') ||
      upper.startsWith('ZING') ||
      upper.startsWith('SGW');
}

/// BLE scanner wrapper.
class BleScanner {
  StreamSubscription<List<ScanResult>>? _subscription;
  final _devices = <String, ScannedDevice>{};
  final _controller = StreamController<List<ScannedDevice>>.broadcast();
  bool _scanning = false;

  Stream<List<ScannedDevice>> get devices => _controller.stream;
  bool get isScanning => _scanning;
  List<ScannedDevice> get currentDevices => _devices.values.toList()
    ..sort((a, b) {
      // System (already-connected) devices first
      if (a.isSystemDevice && !b.isSystemDevice) return -1;
      if (!a.isSystemDevice && b.isSystemDevice) return 1;
      // Then Segway devices
      if (a.isSegway && !b.isSegway) return -1;
      if (!a.isSegway && b.isSegway) return 1;
      // Then by RSSI
      return b.rssi.compareTo(a.rssi);
    });

  /// Fetch devices already connected at the OS level.
  Future<List<ScannedDevice>> getSystemDevices() async {
    // iOS requires service UUIDs to find system-connected peripherals.
    final connected = await FlutterBluePlus.systemDevices([
      Guid(nbService),
      Guid(nordicService),
    ]);
    return connected.map((d) {
      final name = d.platformName.isNotEmpty ? d.platformName : d.remoteId.str;
      return ScannedDevice(
        device: d,
        name: name,
        rssi: 0,
        isSegway: d.platformName.isNotEmpty && isSegwayName(d.platformName),
        isSystemDevice: true,
      );
    }).toList();
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (_scanning) return;
    _scanning = true;
    _devices.clear();

    // Merge already-connected system devices first.
    final systemDevices = await getSystemDevices();
    for (final sd in systemDevices) {
      _devices[sd.id] = sd;
    }
    _controller.add(currentDevices);

    // Cancel any leftover subscription from a previous scan.
    await _subscription?.cancel();

    // Subscribe BEFORE starting scan so we don't miss early results.
    _subscription = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final id = r.device.remoteId.str;
        final name = r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : r.device.platformName.isNotEmpty
                ? r.device.platformName
                : '';
        // Show ALL devices — unnamed ones get their MAC as display name
        final displayName = name.isNotEmpty ? name : id;
        final wasSystem = _devices[id]?.isSystemDevice ?? false;
        _devices[id] = ScannedDevice(
          device: r.device,
          name: displayName,
          rssi: r.rssi,
          isSegway: name.isNotEmpty && isSegwayName(name),
          isSystemDevice: wasSystem,
        );
      }
      _controller.add(currentDevices);
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: true,
      );
    } finally {
      _scanning = false;
    }
    _controller.add(currentDevices);
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanning = false;
    await _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stopScan();
    _controller.close();
  }
}
