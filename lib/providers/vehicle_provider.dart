/// Live vehicle data provider with polling.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../core/logger.dart';
import '../core/protocol/nb_protocol.dart';
import 'connection_provider.dart';
import 'demo_provider.dart';

// ---------------------------------------------------------------------------
// Vehicle data model
// ---------------------------------------------------------------------------

class VehicleData {
  // --- live telemetry ---
  final int? battery; // percentage
  final int? speedRaw; // 0.1 km/h units
  final int? leftMileageRaw; // 0.1 km units
  final int? singleMileageRaw; // u16, 10m units (raw / 100 = km)
  final int? runningTime; // seconds
  final int? aveSpeedRaw; // 0.1 km/h units
  final int? sigMaxSpeedRaw; // 0.1 km/h units
  final int? powerRaw; // watts
  final int? mainPower; // 503=off, 511=on
  final int? rBool; // vehicle status flags
  final int? alarm;
  final int? timeFull; // 65535=N/A
  final int? preciseMileage;
  final int? mileageRaw; // total odometer, meters
  final String? ecuPn; // ECU part number (never used as $ident, see memory)

  // --- feature-flag registers ---
  final int? funBool; // DIS 0x7D
  final int? funAppBool; // DIS 0x8A — feature-capability flags (bit 4=eleBrake avail)
  final int? funAppBool2; // DIS 0x8C — more capability flags (bit 1=TCS avail)
  final int? ctlBool2; // DIS 0x7C

  // --- speed & safety settings ---
  final int? limitSpeedRaw; // DIS 0x93 (whole km/h, 0 = disabled)
  final int? ratedSpeedRaw; // DIS 0x48 (0.1 km/h)
  final int? warn; // DIS 0x75
  final int? autoLock; // DIS 0x85
  final int? alarmVolume; // DIS 0x76
  final int? alarmLevel; // DIS 0x77 — 1=Sensitive, 2=High, 3=Standard, 4=Low
  final int? speedIntensity; // MCU 0x52
  final int? speedSafeLock; // MCU 0x53
  final int? tcs; // MCU 0x55 (global TCS level 0..2)
  final int? slope; // MCU 0x56
  final int? eleBrake; // MCU 0x57

  // --- riding-mode + currently-active gear profile ---
  final int? activeGearMask; // DIS 0xAA — bit field selecting mode
  final int? gearTopSpeed; // MCU 0x31
  final int? gearAccSpeed; // MCU 0x2D
  final int? gearAccSens; // MCU 0x2E
  final int? gearTcs; // MCU 0x2F
  final int? gearNitro; // MCU 0x30 (0/1)
  final int? gearEnergy; // MCU 0x2C

  const VehicleData({
    this.battery,
    this.speedRaw,
    this.leftMileageRaw,
    this.singleMileageRaw,
    this.runningTime,
    this.aveSpeedRaw,
    this.sigMaxSpeedRaw,
    this.powerRaw,
    this.mainPower,
    this.rBool,
    this.alarm,
    this.timeFull,
    this.preciseMileage,
    this.mileageRaw,
    this.ecuPn,
    this.funBool,
    this.funAppBool,
    this.funAppBool2,
    this.ctlBool2,
    this.limitSpeedRaw,
    this.ratedSpeedRaw,
    this.warn,
    this.autoLock,
    this.alarmVolume,
    this.alarmLevel,
    this.speedIntensity,
    this.speedSafeLock,
    this.tcs,
    this.slope,
    this.eleBrake,
    this.activeGearMask,
    this.gearTopSpeed,
    this.gearAccSpeed,
    this.gearAccSens,
    this.gearTcs,
    this.gearNitro,
    this.gearEnergy,
  });

  // --- computed values ---
  // Byte widths + scaling per `device_commands.json` and confirmed
  // against the live E125S dashboard — different registers use
  // different resolutions (even across the same category):
  //   rLeftMileage  (0x25): u16, 0.1 km units
  //   rSingleMileage(0xB9): u16, 10 m units   (× 0.01 = km)
  //   rMileage      (0xB7): u32, 1 m units    (× 0.001 = km)
  //   rRunningTime  (0xBA): u16, seconds
  //   rPower        (0xBD): int16, watts      (signed — regen goes negative)
  double get speed => (speedRaw ?? 0) * 0.1;
  double get leftMileage => (leftMileageRaw ?? 0) * 0.1;
  double get singleMileage => (singleMileageRaw ?? 0) * 0.01;
  double get aveSpeed => (aveSpeedRaw ?? 0) * 0.1;
  double get sigMaxSpeed => (sigMaxSpeedRaw ?? 0) * 0.1;
  double get limitSpeed => (limitSpeedRaw ?? 0).toDouble();
  double get ratedSpeed => (ratedSpeedRaw ?? 0) * 0.1;
  double get mileage => (mileageRaw ?? 0) * 0.001;
  int get power {
    final raw = powerRaw;
    if (raw == null) return 0;
    // u16 → int16: anything above 0x7FFF is a negative wattage in
    // two's-complement (regenerative braking returns power to the
    // battery; firmware reports that as a negative number).
    return raw > 0x7FFF ? raw - 0x10000 : raw;
  }
  bool get isPoweredOn => mainPower != null && (mainPower! & 0x08) != 0;

  String get runningTimeFormatted {
    final s = runningTime ?? 0;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${sec}s';
    return '${sec}s';
  }

  VehicleData copyWith({
    int? battery,
    int? speedRaw,
    int? leftMileageRaw,
    int? singleMileageRaw,
    int? runningTime,
    int? aveSpeedRaw,
    int? sigMaxSpeedRaw,
    int? powerRaw,
    int? mainPower,
    int? rBool,
    int? alarm,
    int? timeFull,
    int? preciseMileage,
    int? mileageRaw,
    String? ecuPn,
    int? funBool,
    int? funAppBool,
    int? funAppBool2,
    int? ctlBool2,
    int? limitSpeedRaw,
    int? ratedSpeedRaw,
    int? warn,
    int? autoLock,
    int? alarmVolume,
    int? alarmLevel,
    int? speedIntensity,
    int? speedSafeLock,
    int? tcs,
    int? slope,
    int? eleBrake,
    int? activeGearMask,
    int? gearTopSpeed,
    int? gearAccSpeed,
    int? gearAccSens,
    int? gearTcs,
    int? gearNitro,
    int? gearEnergy,
  }) =>
      VehicleData(
        battery: battery ?? this.battery,
        speedRaw: speedRaw ?? this.speedRaw,
        leftMileageRaw: leftMileageRaw ?? this.leftMileageRaw,
        singleMileageRaw: singleMileageRaw ?? this.singleMileageRaw,
        runningTime: runningTime ?? this.runningTime,
        aveSpeedRaw: aveSpeedRaw ?? this.aveSpeedRaw,
        sigMaxSpeedRaw: sigMaxSpeedRaw ?? this.sigMaxSpeedRaw,
        powerRaw: powerRaw ?? this.powerRaw,
        mainPower: mainPower ?? this.mainPower,
        rBool: rBool ?? this.rBool,
        alarm: alarm ?? this.alarm,
        timeFull: timeFull ?? this.timeFull,
        preciseMileage: preciseMileage ?? this.preciseMileage,
        mileageRaw: mileageRaw ?? this.mileageRaw,
        ecuPn: ecuPn ?? this.ecuPn,
        funBool: funBool ?? this.funBool,
        funAppBool: funAppBool ?? this.funAppBool,
        funAppBool2: funAppBool2 ?? this.funAppBool2,
        ctlBool2: ctlBool2 ?? this.ctlBool2,
        limitSpeedRaw: limitSpeedRaw ?? this.limitSpeedRaw,
        ratedSpeedRaw: ratedSpeedRaw ?? this.ratedSpeedRaw,
        warn: warn ?? this.warn,
        autoLock: autoLock ?? this.autoLock,
        alarmVolume: alarmVolume ?? this.alarmVolume,
        alarmLevel: alarmLevel ?? this.alarmLevel,
        speedIntensity: speedIntensity ?? this.speedIntensity,
        speedSafeLock: speedSafeLock ?? this.speedSafeLock,
        tcs: tcs ?? this.tcs,
        slope: slope ?? this.slope,
        eleBrake: eleBrake ?? this.eleBrake,
        activeGearMask: activeGearMask ?? this.activeGearMask,
        gearTopSpeed: gearTopSpeed ?? this.gearTopSpeed,
        gearAccSpeed: gearAccSpeed ?? this.gearAccSpeed,
        gearAccSens: gearAccSens ?? this.gearAccSens,
        gearTcs: gearTcs ?? this.gearTcs,
        gearNitro: gearNitro ?? this.gearNitro,
        gearEnergy: gearEnergy ?? this.gearEnergy,
      );
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final vehicleProvider =
    StateNotifierProvider<VehicleNotifier, VehicleData>((ref) {
  final isDemo = ref.watch(demoModeProvider);
  final notifier = isDemo ? DemoVehicleNotifier(ref) : VehicleNotifier(ref);

  if (ref.read(connectionProvider).isConnected) {
    notifier.startPolling();
  }

  ref.listen(connectionProvider, (prev, next) {
    if (next.isConnected) {
      notifier.startPolling();
    } else {
      notifier.stopPolling();
    }
  });
  return notifier;
});

/// Which polling tiers a screen actually needs.
enum PollTier { fast, medium, slow, settings }

class _PollClaim {
  final String by;
  final Set<PollTier> tiers;
  const _PollClaim(this.by, this.tiers);
  @override
  String toString() => '$by{${tiers.map((t) => t.name).join(",")}}';
}

class VehicleNotifier extends StateNotifier<VehicleData> {
  final Ref _ref;
  Timer? _fastTimer; // 500ms — speed, power
  Timer? _medTimer; // 1000ms — running time, sig max speed
  Timer? _slowTimer; // 2000ms — battery, range, mileage, main power
  Timer? _settingsTimer; // 5000ms — catch-up for settings edited elsewhere
  bool _polling = false;

  /// LIFO stack of screens currently interested in polling. Only the
  /// TOP claim's tiers run — screens beneath are preempted, matching
  /// the navigation stack. A screen pushes on [resumePolling] and pops
  /// on [pausePolling].
  final List<_PollClaim> _stack = [];

  /// Declare this screen's live-data needs. Balanced by [pausePolling].
  void resumePolling(Set<PollTier> tiers, {required String by}) {
    _stack.add(_PollClaim(by, tiers));
    talker.info('Poll stack PUSH $by (tiers=${tiers.map((t) => t.name).join(",")}) '
        '→ active: ${_describeStack()}');
  }

  /// Release a previous claim with the same [by] label.
  void pausePolling({required String by}) {
    final idx = _stack.lastIndexWhere((c) => c.by == by);
    if (idx < 0) {
      talker.warning('pausePolling($by): no matching claim on stack');
      return;
    }
    _stack.removeAt(idx);
    talker.info('Poll stack POP $by '
        '→ active: ${_describeStack()}');
  }

  String _describeStack() {
    if (_stack.isEmpty) return '(none)';
    final top = _stack.last;
    return '${top.by}{${top.tiers.map((t) => t.name).join(",")}}';
  }

  /// Tiers the active (topmost) claim wants.
  Set<PollTier> get _activeTiers =>
      _stack.isEmpty ? const {} : _stack.last.tiers;

  bool _tierActive(PollTier t) => _activeTiers.contains(t);

  VehicleNotifier(this._ref) : super(const VehicleData());

  ConnectionNotifier get _conn => _ref.read(connectionProvider.notifier);

  /// Boards that sleep when the vehicle is powered off. Reads to them
  /// return nothing and eat the 4 s timeout budget — skip them until we
  /// see `rMainPower` indicate a live vehicle.
  static const _sleepsWhenOff = <int>{
    /* MCU */ 0x20,
    /* ECU */ 0x25,
    /* BMS1 */ 0x22, /* BMS2 */ 0x23,
  };

  bool _boardAwake(int target) {
    if (!_sleepsWhenOff.contains(target)) return true;
    return state.isPoweredOn;
  }

  /// Read a u16 register, returning null on any error (timeout, disconnect).
  /// Skips asleep boards to avoid wedging the unified BLE queue on a 4 s
  /// timeout that will always fail.
  Future<int?> _safeU16(int target, int register,
      {Duration timeout = const Duration(seconds: 2)}) async {
    if (!_boardAwake(target)) return null;
    try {
      return await _conn.readU16(target, register, timeout: timeout);
    } catch (_) {
      return null;
    }
  }

  /// Read a u32 register, returning null on any error.
  Future<int?> _safeU32(int target, int register,
      {Duration timeout = const Duration(seconds: 2)}) async {
    if (!_boardAwake(target)) return null;
    try {
      return await _conn.readU32(target, register, timeout: timeout);
    } catch (_) {
      return null;
    }
  }

  void startPolling() {
    if (_polling) return;
    _polling = true;

    _readOnce();
    _readSettingsOnce();

    // Fast tier prioritises the speedometer. 250 ms cadence + single
    // read per tick = ~4 updates/s with ~25% BLE utilisation, leaving
    // headroom for the other tiers. Power / sigMax moved to medium.
    _fastTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _pollFast();
    });
    _medTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      _pollMedium();
    });
    _slowTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) {
      _pollSlow();
    });
    _settingsTimer = Timer.periodic(const Duration(milliseconds: 5000), (_) {
      _pollSettings();
    });
  }

  void stopPolling() {
    _polling = false;
    _fastTimer?.cancel();
    _medTimer?.cancel();
    _slowTimer?.cancel();
    _settingsTimer?.cancel();
    state = const VehicleData();
  }

  Future<void> _readOnce() async {
    final mainPower = await _safeU16(boardVcu, regMainPower);
    final funAppBool = await _safeU16(boardDis, regFunAppBool);
    final funAppBool2 = await _safeU16(boardDis, regFunAppBool2);
    final ratedSpeed = await _safeU16(boardDis, regRatedSpeed);
    final limitSpeed = await _safeU16(boardDis, regLimitSpeed);
    final funBool = await _safeU16(boardDis, regFunBool);

    // Read ECU PN ($ident for vehicle actions)
    String? ecuPn;
    try {
      final resp = await _conn.readRegister(boardVcu, regEcuPn, readLen: 14);
      if (resp != null) ecuPn = resp.readAscii(14);
    } catch (_) {}

    state = state.copyWith(
      mainPower: mainPower,
      funAppBool: funAppBool,
      funAppBool2: funAppBool2,
      ratedSpeedRaw: ratedSpeed,
      limitSpeedRaw: limitSpeed,
      funBool: funBool,
      ecuPn: ecuPn,
    );
  }

  /// Public hook for settings screens to re-read the full per-page
  /// register set on mount. Useful after power-on (MCU was asleep when
  /// we connected → all gear values are null until someone forces a
  /// refresh). Idempotent — safe to call on every mount.
  Future<void> refreshSettingsRegisters() async {
    talker.info('Settings: manual refresh triggered');
    await _readSettingsOnce();
    talker.info('Settings: manual refresh done');
  }

  /// One-shot read of every register exposed on the Settings screens.
  /// Values rarely change; the dedicated 5-second timer refreshes them
  /// to catch edits made from the dashboard or the official app.
  Future<void> _readSettingsOnce() async {
    final warn = await _safeU16(boardDis, regWarn);
    final ctlBool2 = await _safeU16(boardDis, regCtlBool2);
    final autoLock = await _safeU16(boardDis, regAutoLock);
    final alarmVol = await _safeU16(boardDis, regAlarmVolume);
    final alarmLvl = await _safeU16(boardDis, regAlarmLevel);
    final activeGear = await _safeU16(boardDis, regBool2);
    if (activeGear == null) {
      talker.info('Settings read: rBool2 (0xAA) raw=null');
    } else {
      final hex = activeGear.toRadixString(16).padLeft(4, '0');
      final bin = activeGear.toRadixString(2).padLeft(8, '0');
      talker.info('Settings read: rBool2 (0xAA) raw=0x$hex (0b$bin, $activeGear)');
    }

    final tcs = await _safeU16(boardMcu, regTcs);
    final slope = await _safeU16(boardMcu, regSlope);
    final eleBrake = await _safeU16(boardMcu, regEleBrake);
    final speedInt = await _safeU16(boardMcu, regSpeedIntensity);
    final speedLock = await _safeU16(boardMcu, regSpeedSafeLock);

    final gearTop = await _safeU16(boardMcu, regGearTopSpeed);
    final gearAccSp = await _safeU16(boardMcu, regGearAccSpeed);
    final gearAccSn = await _safeU16(boardMcu, regGearAccSens);
    final gearTcs = await _safeU16(boardMcu, regGearTcs);
    final gearNitro = await _safeU16(boardMcu, regGearNitro);
    final gearEn = await _safeU16(boardMcu, regGearEnergy);

    state = state.copyWith(
      warn: warn,
      ctlBool2: ctlBool2,
      autoLock: autoLock,
      alarmVolume: alarmVol,
      alarmLevel: alarmLvl,
      activeGearMask: activeGear,
      tcs: tcs,
      slope: slope,
      eleBrake: eleBrake,
      speedIntensity: speedInt,
      speedSafeLock: speedLock,
      gearTopSpeed: gearTop,
      gearAccSpeed: gearAccSp,
      gearAccSens: gearAccSn,
      gearTcs: gearTcs,
      gearNitro: gearNitro,
      gearEnergy: gearEn,
    );
  }

  Future<void> _pollFast() async {
    if (!_polling || !_tierActive(PollTier.fast)) return;
    // Single-register read — keep the fast tier light so speed tracks
    // the throttle instead of queueing behind battery/mileage reads.
    final speed = await _safeU16(boardDis, regSpeed);
    state = state.copyWith(speedRaw: speed);
  }

  Future<void> _pollMedium() async {
    if (!_polling || !_tierActive(PollTier.medium)) return;
    final power = await _safeU16(boardDis, regPower);
    // rRunningTime is u16 (s_data=2 in device_commands.json); reading
    // as u32 either returns null (data.length<4 rejection) or bleeds
    // 2 bytes of neighbouring register memory into the value.
    final runningTime = await _safeU16(boardDis, regRunningTime);
    final sigMax = await _safeU16(boardDis, regSigMaxSpeed);
    state = state.copyWith(
        powerRaw: power, runningTime: runningTime, sigMaxSpeedRaw: sigMax);
  }

  Future<void> _pollSlow() async {
    if (!_polling || !_tierActive(PollTier.slow)) return;
    final battery = await _safeU16(boardDis, regBattery);
    final leftMi = await _safeU16(boardDis, regLeftMileage);
    // rSingleMileage is a u16 on E-series firmware. Reading as u32
    // bleeds 2 bytes of neighbouring register memory into the value
    // and produces nonsensical 10k+ km trips.
    final singleMi = await _safeU16(boardDis, regSingleMileage);
    final aveSpeed = await _safeU16(boardDis, regAveSpeed);
    final mileage = await _safeU32(boardDis, regMileage);
    final rBool = await _safeU16(boardDis, regBool);
    final alarm = await _safeU16(boardDis, regAlarm);
    final mainPower = await _safeU16(boardVcu, regMainPower);
    state = state.copyWith(
      battery: battery,
      leftMileageRaw: leftMi,
      singleMileageRaw: singleMi,
      aveSpeedRaw: aveSpeed,
      mileageRaw: mileage,
      rBool: rBool,
      alarm: alarm,
      mainPower: mainPower,
    );
  }

  /// Periodic refresh of settings registers so the UI stays in sync with
  /// changes made from other apps / the scooter itself.
  Future<void> _pollSettings() async {
    if (!_polling || !_tierActive(PollTier.settings)) return;
    // When the active gear is switched, all six gear-profile registers
    // re-point at the new gear's values. Re-reading once every 5 s keeps
    // the Riding-Modes screen honest without flooding BLE traffic.
    final activeGear = await _safeU16(boardDis, regBool2);
    final limitSpeed = await _safeU16(boardDis, regLimitSpeed);
    final gearTop = await _safeU16(boardMcu, regGearTopSpeed);
    final gearEn = await _safeU16(boardMcu, regGearEnergy);
    state = state.copyWith(
      activeGearMask: activeGear,
      limitSpeedRaw: limitSpeed,
      gearTopSpeed: gearTop,
      gearEnergy: gearEn,
    );
  }

  /// Update individual fields without polling.
  /// Used by settings screens after verified writes.
  void patch({
    int? limitSpeedRaw,
    int? warn,
    int? funBool,
    int? funAppBool,
    int? funAppBool2,
    int? ctlBool2,
    int? mainPower,
    String? ecuPn,
    int? autoLock,
    int? alarmVolume,
    int? alarmLevel,
    int? speedIntensity,
    int? speedSafeLock,
    int? tcs,
    int? slope,
    int? eleBrake,
    int? activeGearMask,
    int? gearTopSpeed,
    int? gearAccSpeed,
    int? gearAccSens,
    int? gearTcs,
    int? gearNitro,
    int? gearEnergy,
  }) {
    state = state.copyWith(
      limitSpeedRaw: limitSpeedRaw,
      warn: warn,
      funBool: funBool,
      funAppBool2: funAppBool2,
      funAppBool: funAppBool,
      ctlBool2: ctlBool2,
      mainPower: mainPower,
      ecuPn: ecuPn,
      autoLock: autoLock,
      alarmVolume: alarmVolume,
      alarmLevel: alarmLevel,
      speedIntensity: speedIntensity,
      speedSafeLock: speedSafeLock,
      tcs: tcs,
      slope: slope,
      eleBrake: eleBrake,
      activeGearMask: activeGearMask,
      gearTopSpeed: gearTopSpeed,
      gearAccSpeed: gearAccSpeed,
      gearAccSens: gearAccSens,
      gearTcs: gearTcs,
      gearNitro: gearNitro,
      gearEnergy: gearEnergy,
    );
  }

  /// Force refresh all data.
  Future<void> refresh() async {
    await _readOnce();
    await _readSettingsOnce();
    await _pollFast();
    await _pollMedium();
    await _pollSlow();
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
