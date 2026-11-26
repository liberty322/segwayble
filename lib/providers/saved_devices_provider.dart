/// Provider for saved BLE devices (quick reconnect list).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/saved_device.dart';
import '../data/session_db.dart';

final savedDevicesProvider =
    AsyncNotifierProvider<SavedDevicesNotifier, List<SavedDevice>>(
        SavedDevicesNotifier.new);

class SavedDevicesNotifier extends AsyncNotifier<List<SavedDevice>> {
  @override
  Future<List<SavedDevice>> build() => SessionDatabase().getSavedDevices();

  Future<void> saveDevice(SavedDevice device) async {
    await SessionDatabase().upsertSavedDevice(device);
    state = AsyncData(await SessionDatabase().getSavedDevices());
  }

  Future<void> removeDevice(String mac) async {
    await SessionDatabase().deleteSavedDevice(mac);
    state = AsyncData(await SessionDatabase().getSavedDevices());
  }
}
