/// GPS speed provider using Geolocator.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// GPS state snapshot.
class GpsState {
  final double? speedMps;
  final double? accuracy;
  final double? lat;
  final double? lng;
  final DateTime? timestamp;
  final String? error;

  const GpsState({
    this.speedMps,
    this.accuracy,
    this.lat,
    this.lng,
    this.timestamp,
    this.error,
  });

  double? get speedKmh => speedMps != null ? speedMps! * 3.6 : null;

  bool get isValid =>
      speedMps != null && speedMps! >= 0 && accuracy != null && accuracy! < 20;
}

/// Stream provider for GPS position updates.
final gpsStateProvider = StreamProvider<GpsState>((ref) async* {
  // Check permission
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    yield const GpsState(error: 'Location permission denied');
    return;
  }

  if (!await Geolocator.isLocationServiceEnabled()) {
    yield const GpsState(error: 'Location services disabled');
    return;
  }

  yield* Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    ),
  ).map((pos) => GpsState(
        speedMps: pos.speed >= 0 ? pos.speed : null,
        accuracy: pos.accuracy,
        lat: pos.latitude,
        lng: pos.longitude,
        timestamp: pos.timestamp,
      ));
});

/// Derived provider: GPS speed in km/h when valid, null otherwise.
final gpsSpeedProvider = Provider<double?>((ref) {
  final gps = ref.watch(gpsStateProvider);
  final state = gps.value;
  return state != null && state.isValid ? state.speedKmh : null;
});
