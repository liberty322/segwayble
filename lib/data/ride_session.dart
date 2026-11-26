/// Ride session and telemetry data models.
library;

/// A recorded ride session.
class RideSession {
  final int? id;
  final DateTime startTime;
  final DateTime? endTime;
  final double maxBleSpeed;
  final double maxGpsSpeed;
  final double avgBleSpeed;
  final double distance; // km
  final double? accel0to45Time; // seconds
  final int duration; // seconds

  const RideSession({
    this.id,
    required this.startTime,
    this.endTime,
    this.maxBleSpeed = 0,
    this.maxGpsSpeed = 0,
    this.avgBleSpeed = 0,
    this.distance = 0,
    this.accel0to45Time,
    this.duration = 0,
  });

  String get durationFormatted {
    final h = duration ~/ 3600;
    final m = (duration % 3600) ~/ 60;
    final s = duration % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'start_time': startTime.millisecondsSinceEpoch,
        'end_time': endTime?.millisecondsSinceEpoch,
        'max_ble_speed': maxBleSpeed,
        'max_gps_speed': maxGpsSpeed,
        'avg_ble_speed': avgBleSpeed,
        'distance': distance,
        'accel_0_45_time': accel0to45Time,
        'duration': duration,
      };

  factory RideSession.fromMap(Map<String, Object?> map) => RideSession(
        id: map['id'] as int?,
        startTime: DateTime.fromMillisecondsSinceEpoch(map['start_time'] as int),
        endTime: map['end_time'] != null
            ? DateTime.fromMillisecondsSinceEpoch(map['end_time'] as int)
            : null,
        maxBleSpeed: (map['max_ble_speed'] as num?)?.toDouble() ?? 0,
        maxGpsSpeed: (map['max_gps_speed'] as num?)?.toDouble() ?? 0,
        avgBleSpeed: (map['avg_ble_speed'] as num?)?.toDouble() ?? 0,
        distance: (map['distance'] as num?)?.toDouble() ?? 0,
        accel0to45Time: (map['accel_0_45_time'] as num?)?.toDouble(),
        duration: (map['duration'] as int?) ?? 0,
      );

  RideSession copyWith({
    int? id,
    DateTime? startTime,
    DateTime? endTime,
    double? maxBleSpeed,
    double? maxGpsSpeed,
    double? avgBleSpeed,
    double? distance,
    double? accel0to45Time,
    int? duration,
  }) =>
      RideSession(
        id: id ?? this.id,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        maxBleSpeed: maxBleSpeed ?? this.maxBleSpeed,
        maxGpsSpeed: maxGpsSpeed ?? this.maxGpsSpeed,
        avgBleSpeed: avgBleSpeed ?? this.avgBleSpeed,
        distance: distance ?? this.distance,
        accel0to45Time: accel0to45Time ?? this.accel0to45Time,
        duration: duration ?? this.duration,
      );
}

/// A single telemetry data point within a session.
class TelemetryPoint {
  final int? id;
  final int sessionId;
  final DateTime timestamp;
  final double bleSpeed;
  final double? gpsSpeed;
  final int power;
  final int battery;
  final double? lat;
  final double? lng;

  const TelemetryPoint({
    this.id,
    required this.sessionId,
    required this.timestamp,
    required this.bleSpeed,
    this.gpsSpeed,
    this.power = 0,
    this.battery = 0,
    this.lat,
    this.lng,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'session_id': sessionId,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'ble_speed': bleSpeed,
        'gps_speed': gpsSpeed,
        'power': power,
        'battery': battery,
        'lat': lat,
        'lng': lng,
      };

  factory TelemetryPoint.fromMap(Map<String, Object?> map) => TelemetryPoint(
        id: map['id'] as int?,
        sessionId: map['session_id'] as int,
        timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
        bleSpeed: (map['ble_speed'] as num?)?.toDouble() ?? 0,
        gpsSpeed: (map['gps_speed'] as num?)?.toDouble(),
        power: (map['power'] as int?) ?? 0,
        battery: (map['battery'] as int?) ?? 0,
        lat: (map['lat'] as num?)?.toDouble(),
        lng: (map['lng'] as num?)?.toDouble(),
      );
}
