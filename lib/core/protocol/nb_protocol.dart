/// Ninebot BLE Encryption2 frame builder/parser.
///
/// Port of nb_protocol.py. Supports Gen2 (0x5AA5) and Gen3 (0x5AB5).
library;

import 'dart:typed_data';

import 'nb_frame.dart';

// ---------------------------------------------------------------------------
// Protocol generation
// ---------------------------------------------------------------------------

enum ProtocolGen {
  gen2, // 0x5AA5 — E125S and older devices
  gen3, // 0x5AB5 — newer devices
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const int sync1 = 0x5A;
const int sync2Gen2 = 0xA5;
const int sync2Gen3 = 0xB5;
const Set<int> validSync2 = {sync2Gen2, sync2Gen3};
const int btId = 0x3E;

// Per-generation config
const Map<ProtocolGen, ({int sync2, int vehicleTarget, int vehicleCmd})>
    protoConfig = {
  ProtocolGen.gen2: (sync2: sync2Gen2, vehicleTarget: 0x09, vehicleCmd: 0x64),
  ProtocolGen.gen3: (sync2: sync2Gen3, vehicleTarget: 0x04, vehicleCmd: 0x03),
};

// Command types
const int cmdRead = 0x01;
const int cmdWrite = 0x02;
const int cmdWriteNr = 0x03;
const int cmdReadResp = 0x04;
const int cmdWriteResp = 0x05;

// Handshake commands
const int cmdPreComm = 0x5B; // 91
const int cmdSetPwd = 0x5C; // 92
const int cmdAuth = 0x5D; // 93

// Board IDs (sendId)
const int boardDis = 0x01; // Display / Dashboard
const int boardBle = 0x04; // BLE module (handshake target)
const int boardVcu = 0x09; // Vehicle Control Unit
const int boardCtrl = 0x20; // Main controller
const int boardMcu = 0x20; // MCU (same as CTRL)
const int boardBms1 = 0x22;
const int boardBms2 = 0x23;
const int boardHep = 0x28;

// Vehicle action registers (Gen2 cmd=0x64 with $ident payload)
const int regOpenAcc = 0x4E;
const int regCloseAcc = 0x46;
const int regOpenTrunk = 0x73;

// DIS dashboard registers (target 0x01)
const int regSn = 0x10;
const int regAlarm = 0x1C;
const int regSigMaxSpeed = 0x24;
const int regLeftMileage = 0x25;
const int regSpeed = 0x26;
const int regAveSpeed = 0x27;
const int regTimeFull = 0x39;
const int regRatedSpeed = 0x48;
const int regWarn = 0x75; // low byte = prompt volume 0–100, high byte = sound preset 0–2
const int regAlarmVolume = 0x76;
const int regAlarmLevel = 0x77; // alarm sensitivity enum 1=Sensitive, 2=High, 3=Standard, 4=Low
const int regLightLevel = 0x7B;
const int regCtlBool2 = 0x7C;
const int regFunBool = 0x7D;
const int regCtlBool = 0x84;
const int regAutoLock = 0x85;
const int regFunAppBool = 0x8A;
const int regFunAppBool2 = 0x8C;
const int regLimitSpeed = 0x93;
const int regPreciseMileage = 0xAF;
const int regBool = 0xB2;
const int regBool2 = 0xAA; // Riding-mode bit-field (Assist/ECO/Coast/Furious/M1/M2)
const int regBattery = 0xB5;
const int regMileage = 0xB7;
const int regSingleMileage = 0xB9;
const int regRunningTime = 0xBA;
const int regPower = 0xBD;

// DIS version registers
const int regDisVersion = 0x1A;
const int regMcuVersion = 0x28;
const int regBms1Version = 0x30;
const int regBms2Version = 0x31;
const int regEcuVersion = 0x4C;
const int regCfgMode = 0x74;

// VCU registers (target 0x09)
const int regMainPower = 0x03;
const int regEcuPn = 0x28;
const int regStateBool = 0x52;

// BLE registers (target 0x04)
const int regBleVersion = 0x68;
const int regFunSupBool = 0x50;

// MCU registers (target 0x20)
const int regMcuMaxSpeed = 0x09;
const int regGearData1 = 0x22;
const int regGearEnergy = 0x2C;
const int regGearAccSpeed = 0x2D;
const int regGearAccSens = 0x2E;
const int regGearTcs = 0x2F;
const int regGearNitro = 0x30;
const int regGearTopSpeed = 0x31;
const int regGearData2 = 0x3A;
const int regSpeedIntensity = 0x52;
const int regSpeedSafeLock = 0x53;
const int regTcs = 0x55;
const int regSlope = 0x56;
const int regEleBrake = 0x57;

// BMS registers
const int regVoltage = 0x1A;
const int regBmsCycleCount = 0x1B;
const int regBmsSoc = 0x32;

// HEP registers
const int regHepLight = 0x0E;

// ---------------------------------------------------------------------------
// Frame building
// ---------------------------------------------------------------------------

/// Build a plaintext Encryption2 frame (App → Device).
///
/// Returns: [0x5A, sync2, len(data), 0x3E, target, cmd, index, data...]
Uint8List buildFrame(int target, int cmd, int index,
    {Uint8List? data, ProtocolGen gen = ProtocolGen.gen2}) {
  final d = data ?? Uint8List(0);
  if (d.length > 255) {
    throw ArgumentError('Data too long: ${d.length} > 255');
  }
  final cfg = protoConfig[gen]!;
  final frame = Uint8List(7 + d.length);
  frame[0] = sync1;
  frame[1] = cfg.sync2;
  frame[2] = d.length;
  frame[3] = btId;
  frame[4] = target;
  frame[5] = cmd;
  frame[6] = index;
  if (d.isNotEmpty) {
    frame.setRange(7, 7 + d.length, d);
  }
  return frame;
}

// ---------------------------------------------------------------------------
// Frame parsing
// ---------------------------------------------------------------------------

/// Parse a decrypted frame (Device → App).
///
/// Expected: [0x5A, sync2, LEN, source_board, 0x3E, cmd, index, data...]
NbFrame? parseFrame(Uint8List decrypted) {
  if (decrypted.length < 7) return null;
  if (decrypted[0] != sync1 || !validSync2.contains(decrypted[1])) return null;
  if (decrypted[4] != btId) return null;

  final length = decrypted[2];
  return NbFrame(
    length: length,
    boardId: decrypted[3],
    cmd: decrypted[5],
    index: decrypted[6],
    data: Uint8List.fromList(
      decrypted.sublist(7, (7 + length).clamp(7, decrypted.length)),
    ),
  );
}

/// Format bytes as hex string for logging.
String frameHex(Uint8List data) =>
    data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

// ---------------------------------------------------------------------------
// Convenience builders — Handshake
// ---------------------------------------------------------------------------

Uint8List buildPreComm({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildFrame(boardBle, cmdPreComm, 0x00, gen: gen);

Uint8List buildSetPwd(Uint8List password, {ProtocolGen gen = ProtocolGen.gen2}) =>
    buildFrame(boardBle, cmdSetPwd, 0x00,
        data: Uint8List.fromList(password.sublist(0, 16)), gen: gen);

Uint8List buildAuth(Uint8List sn, {ProtocolGen gen = ProtocolGen.gen2}) =>
    buildFrame(boardBle, cmdAuth, 0x00,
        data: Uint8List.fromList(sn.sublist(0, sn.length < 14 ? sn.length : 14)),
        gen: gen);

// ---------------------------------------------------------------------------
// Convenience builders — Register read/write
// ---------------------------------------------------------------------------

Uint8List buildRead(int target, int register, {int readLen = 2,
    ProtocolGen gen = ProtocolGen.gen2}) =>
    buildFrame(target, cmdRead, register,
        data: Uint8List.fromList([readLen]), gen: gen);

Uint8List buildWriteNr(int target, int register, Uint8List data,
    {ProtocolGen gen = ProtocolGen.gen2}) =>
    buildFrame(target, cmdWriteNr, register, data: data, gen: gen);

// ---------------------------------------------------------------------------
// Dashboard reads
// ---------------------------------------------------------------------------

Uint8List buildReadSn({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regSn, readLen: 14, gen: gen);

Uint8List buildReadBattery({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regBattery, gen: gen);

Uint8List buildReadSpeedLive({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regSpeed, gen: gen);

Uint8List buildReadLeftMileage({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regLeftMileage, gen: gen);

Uint8List buildReadMileage({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regMileage, readLen: 4, gen: gen);

Uint8List buildReadSingleMileage({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regSingleMileage, gen: gen);

Uint8List buildReadRunningTime({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regRunningTime, gen: gen);

Uint8List buildReadAlarm({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regAlarm, gen: gen);

Uint8List buildReadRatedSpeed({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regRatedSpeed, gen: gen);

Uint8List buildReadPower({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regPower, gen: gen);

Uint8List buildReadSpeedLimit({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regLimitSpeed, gen: gen);

Uint8List buildReadBool({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regBool, gen: gen);

Uint8List buildReadTimeFull({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regTimeFull, gen: gen);

Uint8List buildReadPreciseMileage({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regPreciseMileage, gen: gen);

Uint8List buildReadFunBool({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regFunBool, gen: gen);

Uint8List buildReadCtlBool2({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regCtlBool2, gen: gen);

Uint8List buildReadWarn({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regWarn, gen: gen);

Uint8List buildReadAveSpeed({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regAveSpeed, gen: gen);

Uint8List buildReadSigMaxSpeed({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regSigMaxSpeed, gen: gen);

// VCU reads
Uint8List buildReadMainPower({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardVcu, regMainPower, gen: gen);

Uint8List buildReadEcuPn({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardVcu, regEcuPn, readLen: 14, gen: gen);

// BLE reads
Uint8List buildReadFunSupBool({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardBle, regFunSupBool, readLen: 6, gen: gen);

// Version reads
Uint8List buildReadDisVersion({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regDisVersion, gen: gen);

Uint8List buildReadMcuVersion({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regMcuVersion, gen: gen);

Uint8List buildReadBleVersion({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardBle, regBleVersion, gen: gen);

Uint8List buildReadEcuVersion({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regEcuVersion, gen: gen);

Uint8List buildReadBms1Version({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regBms1Version, gen: gen);

// Feature flags
Uint8List buildReadFunAppBool({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regFunAppBool, gen: gen);

Uint8List buildReadCfgMode({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regCfgMode, gen: gen);

// BMS reads
Uint8List buildReadVoltage({int bms = boardBms1, ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(bms, regVoltage, gen: gen);

Uint8List buildReadBmsSoc({int bms = boardBms1, ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(bms, regBmsSoc, gen: gen);

Uint8List buildReadCycleCount({int bms = boardBms1, ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(bms, regBmsCycleCount, gen: gen);

// ---------------------------------------------------------------------------
// Settings writes
// ---------------------------------------------------------------------------

Uint8List buildSetWarn(int value, {ProtocolGen gen = ProtocolGen.gen2}) {
  final data = Uint8List(2);
  ByteData.sublistView(data).setUint16(0, value, Endian.little);
  return buildWriteNr(boardDis, regWarn, data, gen: gen);
}

Uint8List buildSetCfgMode(int mode, {ProtocolGen gen = ProtocolGen.gen2}) {
  final data = Uint8List(2);
  ByteData.sublistView(data).setUint16(0, mode, Endian.little);
  return buildWriteNr(boardDis, regCfgMode, data, gen: gen);
}

Uint8List buildWriteSpeed(int speedKmh, {ProtocolGen gen = ProtocolGen.gen2}) {
  final data = Uint8List(2);
  ByteData.sublistView(data).setUint16(0, speedKmh, Endian.little);
  return buildWriteNr(boardDis, regLimitSpeed, data, gen: gen);
}

// MCU gear writes
Uint8List buildSetGearTopSpeed(int speed, {ProtocolGen gen = ProtocolGen.gen2}) {
  final data = Uint8List(2);
  ByteData.sublistView(data).setUint16(0, speed, Endian.little);
  return buildWriteNr(boardMcu, regGearTopSpeed, data, gen: gen);
}

Uint8List buildSetGearAccSpeed(int value, {ProtocolGen gen = ProtocolGen.gen2}) {
  final data = Uint8List(2);
  ByteData.sublistView(data).setUint16(0, value, Endian.little);
  return buildWriteNr(boardMcu, regGearAccSpeed, data, gen: gen);
}

Uint8List buildSetGearAccSens(int value, {ProtocolGen gen = ProtocolGen.gen2}) {
  final data = Uint8List(2);
  ByteData.sublistView(data).setUint16(0, value, Endian.little);
  return buildWriteNr(boardMcu, regGearAccSens, data, gen: gen);
}

Uint8List buildSetGearTcs(int value, {ProtocolGen gen = ProtocolGen.gen2}) {
  final data = Uint8List(2);
  ByteData.sublistView(data).setUint16(0, value, Endian.little);
  return buildWriteNr(boardMcu, regGearTcs, data, gen: gen);
}

Uint8List buildSetGearNitro(bool on, {ProtocolGen gen = ProtocolGen.gen2}) {
  final data = Uint8List(2);
  ByteData.sublistView(data).setUint16(0, on ? 1 : 0, Endian.little);
  return buildWriteNr(boardMcu, regGearNitro, data, gen: gen);
}

Uint8List buildSetGearEnergy(int value, {ProtocolGen gen = ProtocolGen.gen2}) {
  final data = Uint8List(2);
  ByteData.sublistView(data).setUint16(0, value, Endian.little);
  return buildWriteNr(boardMcu, regGearEnergy, data, gen: gen);
}

// ---------------------------------------------------------------------------
// MCU safety/traction reads + writes
// ---------------------------------------------------------------------------

Uint8List buildReadSpeedIntensity({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardMcu, regSpeedIntensity, gen: gen);

Uint8List buildReadSpeedSafeLock({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardMcu, regSpeedSafeLock, gen: gen);

Uint8List buildReadTcs({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardMcu, regTcs, gen: gen);

Uint8List buildReadSlope({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardMcu, regSlope, gen: gen);

Uint8List buildReadEleBrake({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardMcu, regEleBrake, gen: gen);

/// Read the full 32-byte gear-profile blob for Custom M1.
Uint8List buildReadGearData1({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardMcu, regGearData1, readLen: 32, gen: gen);

/// Read the full 32-byte gear-profile blob for Custom M2.
Uint8List buildReadGearData2({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardMcu, regGearData2, readLen: 32, gen: gen);

Uint8List _setU16(int target, int reg, int value, ProtocolGen gen) {
  final data = Uint8List(2);
  ByteData.sublistView(data).setUint16(0, value, Endian.little);
  return buildWriteNr(target, reg, data, gen: gen);
}

Uint8List buildSetTcs(int level, {ProtocolGen gen = ProtocolGen.gen2}) =>
    _setU16(boardMcu, regTcs, level, gen);

Uint8List buildSetSlope(int mode, {ProtocolGen gen = ProtocolGen.gen2}) =>
    _setU16(boardMcu, regSlope, mode, gen);

Uint8List buildSetEleBrake(int value, {ProtocolGen gen = ProtocolGen.gen2}) =>
    _setU16(boardMcu, regEleBrake, value, gen);

Uint8List buildSetSpeedIntensity(int value, {ProtocolGen gen = ProtocolGen.gen2}) =>
    _setU16(boardMcu, regSpeedIntensity, value, gen);

Uint8List buildSetSpeedSafeLock(int value, {ProtocolGen gen = ProtocolGen.gen2}) =>
    _setU16(boardMcu, regSpeedSafeLock, value, gen);

// ---------------------------------------------------------------------------
// DIS riding-mode selector (rBool2)
// ---------------------------------------------------------------------------

Uint8List buildReadBool2({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regBool2, gen: gen);

/// Write the riding-mode bitmask. Bits: 1=ECO, 2=Coast, 3=Furious, 4=M1, 5=M2.
Uint8List buildSetBool2(int mask, {ProtocolGen gen = ProtocolGen.gen2}) =>
    _setU16(boardDis, regBool2, mask, gen);

// ---------------------------------------------------------------------------
// DIS misc reads referenced by the new settings UI
// ---------------------------------------------------------------------------

Uint8List buildReadAutoLock({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regAutoLock, gen: gen);

Uint8List buildReadAlarmVolume({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regAlarmVolume, gen: gen);

Uint8List buildReadAlarmLevel({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildRead(boardDis, regAlarmLevel, gen: gen);

Uint8List buildSetAutoLock(int value, {ProtocolGen gen = ProtocolGen.gen2}) =>
    _setU16(boardDis, regAutoLock, value, gen);

Uint8List buildSetAlarmVolume(int value, {ProtocolGen gen = ProtocolGen.gen2}) =>
    _setU16(boardDis, regAlarmVolume, value, gen);

Uint8List buildSetAlarmLevel(int level, {ProtocolGen gen = ProtocolGen.gen2}) =>
    _setU16(boardDis, regAlarmLevel, level, gen);

/// Pack rWarn 16-bit value from its two fields. Low byte = prompt volume,
/// high byte = sound preset (0=Sound1, 1=Sound2, 2=Sound3).
int packWarn({required int volume, required int preset}) =>
    ((preset & 0xFF) << 8) | (volume & 0xFF);
int warnVolume(int warn) => warn & 0xFF;
int warnPreset(int warn) => (warn >> 8) & 0xFF;

// ---------------------------------------------------------------------------
// Vehicle actions (Gen2: VCU cmd=0x64, Gen3: BLE cmd=0x03)
// ---------------------------------------------------------------------------

Uint8List _buildVehicleAction(int register, Uint8List ident,
    {ProtocolGen gen = ProtocolGen.gen2}) {
  final cfg = protoConfig[gen]!;
  return buildFrame(cfg.vehicleTarget, cfg.vehicleCmd, register,
      data: ident, gen: gen);
}

Uint8List buildOpenAcc(Uint8List ident, {ProtocolGen gen = ProtocolGen.gen2}) =>
    _buildVehicleAction(regOpenAcc, ident, gen: gen);

Uint8List buildCloseAcc(Uint8List ident, {ProtocolGen gen = ProtocolGen.gen2}) =>
    _buildVehicleAction(regCloseAcc, ident, gen: gen);

Uint8List buildOpenTrunk(Uint8List ident, {ProtocolGen gen = ProtocolGen.gen2}) =>
    _buildVehicleAction(regOpenTrunk, ident, gen: gen);

// ---------------------------------------------------------------------------
// Sound / light one-shot actions
// ---------------------------------------------------------------------------

/// "Honk and flash lights" — device plays its alarm sound and flashes lights.
/// Spec: `device_commands.json` name="playSound", module="dis", s_cmd=0x11,
/// ops="writeNR", no index/payload.
Uint8List buildPlaySound({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildFrame(boardDis, 0x11, 0x00, gen: gen);

/// Lights-only flash (no sound). Spec: playLight — module="hep", s_cmd=0x11,
/// s_index=1, ops="writeNR".
Uint8List buildPlayLight({ProtocolGen gen = ProtocolGen.gen2}) =>
    buildFrame(boardHep, 0x11, 0x01, gen: gen);
