/// Session recording provider with auto-start/stop.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/ride_session.dart';
import '../data/session_db.dart';
import 'connection_provider.dart';
import 'demo_provider.dart';
import 'gps_provider.dart';
import 'vehicle_provider.dart';

enum RecordingState { idle, recording }

class SessionRecordingState {
  final RecordingState state;
  final int? sessionId;
  final DateTime? startTime;
  final bool autoStarted;

  const SessionRecordingState({
    this.state = RecordingState.idle,
    this.sessionId,
    this.startTime,
    this.autoStarted = false,
  });

  int get elapsed => startTime != null
      ? DateTime.now().difference(startTime!).inSeconds
      : 0;

  String get elapsedFormatted {
    final s = elapsed;
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
}

final sessionRecordingProvider = StateNotifierProvider<
    SessionRecordingNotifier, SessionRecordingState>((ref) {
  final notifier = SessionRecordingNotifier(ref);
  ref.onDispose(() => notifier.dispose());
  return notifier;
});

class SessionRecordingNotifier extends StateNotifier<SessionRecordingState> {
  final Ref _ref;
  final _db = SessionDatabase();
  Timer? _captureTimer;
  Timer? _autoStopTimer;

  // Running stats
  double _maxBleSpeed = 0;
  double _maxGpsSpeed = 0;
  double _speedSum = 0;
  int _speedCount = 0;
  double _startMileage = 0;

  // 0-45 tracking
  bool _tracking0to45 = false;
  DateTime? _accel0to45Start;
  double? _best0to45Time;

  SessionRecordingNotifier(this._ref)
      : super(const SessionRecordingState()) {
    // Watch vehicle speed for auto-start/stop
    _ref.listen(vehicleProvider, (prev, next) {
      _onSpeedChanged(next.speed);
    });
  }

  void _onSpeedChanged(double speed) {
    final isDemo = _ref.read(demoModeProvider);
    final isConnected = _ref.read(connectionProvider).isConnected;

    if (state.state == RecordingState.idle &&
        speed > 3 &&
        isConnected &&
        !isDemo) {
      // Auto-start
      start(auto: true);
    }

    if (state.state == RecordingState.recording) {
      if (speed < 1) {
        // Start auto-stop timer (30s of < 1 km/h)
        _autoStopTimer ??= Timer(const Duration(seconds: 30), () {
          if (state.state == RecordingState.recording) {
            stop();
          }
        });
      } else {
        // Reset auto-stop timer
        _autoStopTimer?.cancel();
        _autoStopTimer = null;
      }
    }
  }

  Future<void> start({bool auto = false}) async {
    if (state.state == RecordingState.recording) return;

    final now = DateTime.now();
    final vehicle = _ref.read(vehicleProvider);

    _maxBleSpeed = 0;
    _maxGpsSpeed = 0;
    _speedSum = 0;
    _speedCount = 0;
    _startMileage = vehicle.singleMileage;
    _tracking0to45 = false;
    _accel0to45Start = null;
    _best0to45Time = null;

    final session = RideSession(startTime: now);
    final id = await _db.insertSession(session);

    state = SessionRecordingState(
      state: RecordingState.recording,
      sessionId: id,
      startTime: now,
      autoStarted: auto,
    );

    // Capture telemetry every 500ms
    _captureTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _captureTick();
    });
  }

  void _captureTick() {
    if (state.state != RecordingState.recording || state.sessionId == null) {
      return;
    }

    final vehicle = _ref.read(vehicleProvider);
    final gpsSpeed = _ref.read(gpsSpeedProvider);
    final gps = _ref.read(gpsStateProvider);
    final gpsState = gps.value;

    final bleSpeed = vehicle.speed;

    // Update running stats
    if (bleSpeed > _maxBleSpeed) _maxBleSpeed = bleSpeed;
    if (gpsSpeed != null && gpsSpeed > _maxGpsSpeed) _maxGpsSpeed = gpsSpeed;
    _speedSum += bleSpeed;
    _speedCount++;

    // 0-45 tracking: start at 5 km/h, stop at 45 km/h
    if (!_tracking0to45 && bleSpeed >= 5 && bleSpeed < 10) {
      _tracking0to45 = true;
      _accel0to45Start = DateTime.now();
    }
    if (_tracking0to45 && bleSpeed >= 45 && _accel0to45Start != null) {
      final time =
          DateTime.now().difference(_accel0to45Start!).inMilliseconds / 1000.0;
      if (_best0to45Time == null || time < _best0to45Time!) {
        _best0to45Time = time;
      }
      _tracking0to45 = false;
    }
    // Reset if speed drops below 3 during tracking
    if (_tracking0to45 && bleSpeed < 3) {
      _tracking0to45 = false;
      _accel0to45Start = null;
    }

    // Write telemetry point
    _db.insertTelemetry(TelemetryPoint(
      sessionId: state.sessionId!,
      timestamp: DateTime.now(),
      bleSpeed: bleSpeed,
      gpsSpeed: gpsSpeed,
      power: vehicle.power,
      battery: vehicle.battery ?? 0,
      lat: gpsState?.lat,
      lng: gpsState?.lng,
    ));
  }

  Future<void> stop() async {
    if (state.state != RecordingState.recording || state.sessionId == null) {
      return;
    }

    _captureTimer?.cancel();
    _captureTimer = null;
    _autoStopTimer?.cancel();
    _autoStopTimer = null;

    final vehicle = _ref.read(vehicleProvider);
    final now = DateTime.now();
    final duration = state.startTime != null
        ? now.difference(state.startTime!).inSeconds
        : 0;
    final distance = vehicle.singleMileage - _startMileage;

    final session = RideSession(
      id: state.sessionId,
      startTime: state.startTime!,
      endTime: now,
      maxBleSpeed: _maxBleSpeed,
      maxGpsSpeed: _maxGpsSpeed,
      avgBleSpeed: _speedCount > 0 ? _speedSum / _speedCount : 0,
      distance: distance > 0 ? distance : 0,
      accel0to45Time: _best0to45Time,
      duration: duration,
    );

    await _db.updateSession(session);

    state = const SessionRecordingState();

    // Invalidate session list
    _ref.invalidate(sessionListProvider);
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    _autoStopTimer?.cancel();
    super.dispose();
  }
}

/// List of all past sessions.
final sessionListProvider = FutureProvider<List<RideSession>>((ref) async {
  final db = SessionDatabase();
  return db.getAllSessions();
});
