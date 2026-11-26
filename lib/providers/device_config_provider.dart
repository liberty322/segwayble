/// Device config provider — loads and provides active device config.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/device_config.dart';
import '../data/device_registry.dart';

/// Global device registry.
final deviceRegistryProvider = FutureProvider<DeviceRegistry>((ref) async {
  return DeviceRegistry.load();
});

/// Active device entry (selected by user or auto-matched).
final activeDeviceEntryProvider = StateProvider<DeviceEntry?>((ref) => null);

/// Active device config (loaded from assets).
final activeDeviceConfigProvider = FutureProvider<DeviceConfig?>((ref) async {
  final entry = ref.watch(activeDeviceEntryProvider);
  if (entry == null) return null;
  final registry = await ref.watch(deviceRegistryProvider.future);
  return registry.loadConfig(entry);
});
