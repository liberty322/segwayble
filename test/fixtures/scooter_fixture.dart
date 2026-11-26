/// Default register snapshot for a virtual E125S-class vehicle.
///
/// Values are obviously-fake placeholders — just structurally-valid
/// stand-ins for what a real device emits. Real captured bytes are not
/// checked into this repo.
library;

import 'dart:typed_data';

import 'package:app/core/protocol/nb_protocol.dart';

/// Static fixture used by tests unless they override it.
class ScooterFixture {
  /// BT broadcast name used as key1 during PRE_COMM. On real hardware
  /// this equals the serial number printed on the vehicle.
  final String btName;

  /// 14-byte ASCII serial number returned in PRE_COMM_RESP and expected
  /// back from the app in the AUTH frame.
  final String serialNumber;

  /// ECU part number string returned for READ (0x09, 0x28). Read by the
  /// Segway app during startup. NOTE: not used as the vehicle-action
  /// payload — see [commandIdent].
  final String ecuPn;

  /// 16-byte command-authorization ident that the device requires as
  /// the payload of any vehicle-action frame (cmd=0x64 on target=VCU).
  ///
  /// On real hardware this is cloud-issued at pairing and persisted on
  /// iOS under UserDefaults key `{serialNumber}_ident` (32-char hex).
  /// Frames with a mismatched payload are silently ignored by firmware.
  ///
  /// Note: unrelated to the "airlock" proximity-unlock feature (separate
  /// iBeacon code path).
  final Uint8List commandIdent;

  /// 16-byte mKeyAuth that the device advertises in PRE_COMM_RESP.
  final Uint8List mKeyAuth;

  /// 16-byte stored password the app caches from a previous pairing
  /// (iOS UserDefaults key `{serialNumber}_decrypt`).
  final Uint8List storedPassword;

  /// Values for register reads, keyed by (target, register). Values are
  /// the raw little-endian bytes the READ_RESP should return.
  final Map<(int, int), Uint8List> registers;

  /// Boards the device has wired up. Reads to boards NOT in this set
  /// receive no response (matches real firmware: E125S ignores reads to
  /// battery slots 2-7 etc.).
  final Set<int> knownBoards;

  ScooterFixture({
    required this.btName,
    required this.serialNumber,
    required this.ecuPn,
    required this.commandIdent,
    required this.mKeyAuth,
    required this.storedPassword,
    required this.registers,
    Set<int>? knownBoards,
  }) : knownBoards = knownBoards ?? _defaultKnownBoards;

  static const _defaultKnownBoards = <int>{
    boardDis, boardBle, boardVcu, boardMcu, boardBms1, boardBms2, boardHep,
  };

  /// Default E125S-class snapshot. All values are structurally-valid
  /// placeholders; nothing here corresponds to a real device.
  static ScooterFixture defaultE125s() => ScooterFixture(
        btName: 'S1DCA123456789',
        serialNumber: 'S1DCA123456789',
        ecuPn: 'FAKEECUPN12345',
        // `{sn}_ident` stand-in — 16 bytes, visually distinct from pwd.
        commandIdent: Uint8List.fromList([
          0xff, 0xee, 0xdd, 0xcc, 0xbb, 0xaa, 0x99, 0x88,
          0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x00,
        ]),
        // mKeyAuth stand-in — 16 bytes, deterministic pattern so
        // expected crypto outputs are reproducible.
        mKeyAuth: Uint8List.fromList([
          0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7,
          0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf,
        ]),
        // `{sn}_decrypt` stand-in — 16 bytes.
        storedPassword: Uint8List.fromList([
          0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
          0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff,
        ]),
        registers: {
          // DIS — dashboard. Values chosen to look obviously-fake while
          // still hitting the value decoders in decrypt_capture.py etc.
          (boardDis, regSn): _ascii('S1DCA123456789', 14),
          (boardDis, regBattery): _u16(87),
          (boardDis, regSpeed): _u16(0),
          (boardDis, regAveSpeed): _u16(0),
          (boardDis, regLeftMileage): _u16(551),        // 55.1 km
          (boardDis, regMileage): _u32(123456),
          (boardDis, regSingleMileage): _u32(420),
          (boardDis, regRunningTime): _u32(3660),
          (boardDis, regPreciseMileage): _u32(12345600),
          (boardDis, regAlarm): _u16(0),
          (boardDis, regRatedSpeed): _u16(250),
          (boardDis, regLimitSpeed): _u16(0),
          (boardDis, regPower): _u16(0),
          (boardDis, regBool): _u16(0x0b42),
          (boardDis, regTimeFull): _u32(0),
          (boardDis, regFunBool): _u16(0x742e),
          (boardDis, regCtlBool2): _u16(0x0004),
          (boardDis, regWarn): _u16(0),
          (boardDis, regSigMaxSpeed): _u16(250),
          (boardDis, regDisVersion): _u16(0x0364),
          (boardDis, regMcuVersion): _u16(0x0616),
          (boardDis, regBms1Version): _u16(0x0335),
          (boardDis, regEcuVersion): _u16(0x0141),
          (boardDis, regCfgMode): _u16(0),
          (boardDis, regFunAppBool): _u16(0),
          (boardDis, regFunAppBool2): _u16(0),
          (boardDis, 0x50): _ascii('FAKEDISPN12345', 14),

          // VCU — vehicle controller (E125S)
          (boardVcu, regMainPower): _u16(0x03f7),
          (boardVcu, regEcuPn): _ascii('FAKEECUPN12345', 14),
          (boardVcu, regStateBool): _u16(0),

          // BLE module
          (boardBle, regBleVersion): _u16(0x0138),
          (boardBle, regFunSupBool): Uint8List.fromList(
              [0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),

          // MCU
          (boardMcu, regMcuMaxSpeed): _u16(250),
          (boardMcu, regGearTopSpeed): _u16(250),

          // BMS
          (boardBms1, regVoltage): _u16(4210),
          (boardBms1, regBmsSoc): _u16(87),
          (boardBms1, regBmsCycleCount): _u16(42),
        },
      );
}

Uint8List _u16(int v) {
  final b = Uint8List(2);
  ByteData.sublistView(b).setUint16(0, v, Endian.little);
  return b;
}

Uint8List _u32(int v) {
  final b = Uint8List(4);
  ByteData.sublistView(b).setUint32(0, v, Endian.little);
  return b;
}

Uint8List _ascii(String s, int len) {
  final b = Uint8List(len);
  final codes = s.codeUnits;
  for (var i = 0; i < codes.length && i < len; i++) {
    b[i] = codes[i];
  }
  return b;
}
