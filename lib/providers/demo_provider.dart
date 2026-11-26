/// Demo mode — fills the app with animated dummy data without BLE.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/protocol/nb_frame.dart';
import '../core/protocol/nb_protocol.dart';
import 'connection_provider.dart';
import 'vehicle_provider.dart';

// ---------------------------------------------------------------------------
// Global demo mode toggle
// ---------------------------------------------------------------------------

final demoModeProvider = StateProvider<bool>((ref) => false);

// ---------------------------------------------------------------------------
// Mock register map (realistic E125S values)
// ---------------------------------------------------------------------------

/// Key: (boardId, register) → value (int) or String for ASCII registers.
final Map<(int, int), Object> _mockRegisters = {
  // DIS registers
  (boardDis, regBattery): 78,
  (boardDis, regSpeed): 0, // animated
  (boardDis, regPower): 0, // animated
  (boardDis, regLeftMileage): 432, // 43.2 km
  (boardDis, regSingleMileage): 5420000, // 5.42 km (u32, meters)
  (boardDis, regRunningTime): 1847, // 30m 47s (u32)
  (boardDis, regAveSpeed): 178, // 17.8 km/h
  (boardDis, regSigMaxSpeed): 289, // 28.9 km/h
  (boardDis, regLimitSpeed): 25, // 25 km/h (whole km/h, no scaling)
  (boardDis, regRatedSpeed): 450, // 45 km/h
  (boardDis, regFunBool): 3, // auto-lock + speed warn
  (boardDis, regFunAppBool): 1,
  (boardDis, regWarn): 20, // preset 1
  (boardDis, regBool): 0,
  (boardDis, regAlarm): 0,
  (boardDis, regSn): 'S1DXXXXXXXXX01',
  (boardDis, regDisVersion): 0x0123,
  (boardDis, regMcuVersion): 0x0234,
  (boardDis, regEcuVersion): 0x0345,
  (boardDis, regBms1Version): 0x0214,
  (boardDis, regMileage): 42850000, // 42.85 km (u32, meters)

  // VCU registers
  (boardVcu, regMainPower): 0x0508, // powered on (bit 3 set)
  (boardVcu, regEcuPn): '21.01.0076.03',

  // BLE registers
  (boardBle, regBleVersion): 0x0112,

  // BMS registers
  (boardBms1, regVoltage): 6000, // 60.00 V
  (boardBms1, regBmsCycleCount): 42,
};

// ---------------------------------------------------------------------------
// DemoConnectionNotifier
// ---------------------------------------------------------------------------

class DemoConnectionNotifier extends ConnectionNotifier {
  DemoConnectionNotifier() {
    // Immediately set state to connected.
    state = const BleConnectionState(
      phase: ConnectionPhase.connected,
      deviceName: 'S1DXXXXXXXXX01',
      serialNumber: 'S1DXXXXXXXXX01',
      message: 'Demo mode',
    );
  }

  @override
  Future<void> connect(
    BluetoothDevice device, {
    String? btName,
    ProtocolGen gen = ProtocolGen.gen2,
    Uint8List? storedPassword,
    Uint8List? commandIdent,
  }) async {
    // No-op in demo mode.
  }

  @override
  Future<void> disconnect() async {
    state = const BleConnectionState();
  }

  @override
  Future<NbFrame?> sendAndRecv(Uint8List plaintext,
      {Duration timeout = const Duration(seconds: 5)}) async {
    return null;
  }

  @override
  Future<void> sendOnly(Uint8List plaintext) async {
    // No-op.
  }

  @override
  Future<NbFrame?> readRegister(int target, int register,
      {int readLen = 2,
      Duration timeout = const Duration(seconds: 5)}) async {
    final value = _mockRegisters[(target, register)];
    if (value == null) return null;

    Uint8List data;
    if (value is String) {
      // ASCII register (SN, ECU PN)
      final bytes = value.codeUnits;
      data = Uint8List(readLen);
      for (var i = 0; i < bytes.length && i < readLen; i++) {
        data[i] = bytes[i];
      }
    } else if (value is int) {
      if (readLen >= 4) {
        data = Uint8List(4);
        ByteData.sublistView(data).setUint32(0, value, Endian.little);
      } else {
        data = Uint8List(2);
        ByteData.sublistView(data).setUint16(0, value & 0xFFFF, Endian.little);
      }
    } else {
      return null;
    }

    return NbFrame(
      length: data.length,
      boardId: target,
      cmd: cmdReadResp,
      index: register,
      data: data,
    );
  }

  @override
  Future<int?> readU16(int target, int register,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final value = _mockRegisters[(target, register)];
    if (value is int) return value & 0xFFFF;
    return null;
  }

  @override
  Future<int?> readU32(int target, int register,
      {int readLen = 4,
      Duration timeout = const Duration(seconds: 5)}) async {
    final value = _mockRegisters[(target, register)];
    if (value is int) return value;
    return null;
  }

  @override
  Future<void> sendRaw(Uint8List data) async {
    // No-op in demo mode.
  }

  @override
  Future<void> writeRegister(int target, int register, Uint8List data) async {
    // Update mock map so reads reflect the write.
    if (data.length >= 2) {
      final value = ByteData.sublistView(data).getUint16(0, Endian.little);
      _mockRegisters[(target, register)] = value;
    }
  }

  @override
  Future<int?> writeAndVerifyU16(int target, int register, int value) async {
    _mockRegisters[(target, register)] = value;
    return value;
  }
}

// ---------------------------------------------------------------------------
// DemoVehicleNotifier
// ---------------------------------------------------------------------------

class DemoVehicleNotifier extends VehicleNotifier {
  Timer? _animTimer;
  int _tick = 0;

  DemoVehicleNotifier(super.ref);

  @override
  void startPolling() {
    // Set initial static values.
    state = const VehicleData(
      battery: 78,
      speedRaw: 0,
      powerRaw: 0,
      leftMileageRaw: 432,
      singleMileageRaw: 5420000,
      runningTime: 1847,
      aveSpeedRaw: 178,
      sigMaxSpeedRaw: 289,
      mainPower: 0x0508,
      rBool: 0,
      alarm: 0,
      funBool: 3,
      funAppBool: 1,
      limitSpeedRaw: 25,
      ratedSpeedRaw: 450,
      warn: 20,
      mileageRaw: 42850000,
      ecuPn: '21.01.0076.03',
    );

    _tick = 0;
    _animTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _tick++;
      final t = _tick.toDouble();

      // Speed: sine wave 12 + 8*sin(t*0.3) → 4–20 km/h → raw = speed * 10
      final speed = 12.0 + 8.0 * sin(t * 0.3);
      final speedRaw = (speed * 10).round();

      // Power: proportional to speed
      final powerRaw = (speed * 35).round();

      // Running time: +1 every 2 ticks (1 second real-time)
      final runningTime = 1847 + (_tick ~/ 2);

      // Trip distance: accumulate proportional to speed (m per 500ms tick)
      // speed km/h * 1000/3600 * 0.5 = speed * 0.1389 meters per tick
      final addedMeters = (speed * 0.1389 * _tick).round();
      final singleMileageRaw = 5420000 + addedMeters;

      // Battery: tick down 1% every ~120 ticks (60s)
      final batteryDrop = _tick ~/ 120;
      final battery = (78 - batteryDrop).clamp(0, 100);

      state = state.copyWith(
        speedRaw: speedRaw,
        powerRaw: powerRaw,
        runningTime: runningTime,
        singleMileageRaw: singleMileageRaw,
        battery: battery,
      );
    });
  }

  @override
  void stopPolling() {
    _animTimer?.cancel();
    _animTimer = null;
    state = const VehicleData();
  }

  @override
  void dispose() {
    _animTimer?.cancel();
    super.dispose();
  }
}
