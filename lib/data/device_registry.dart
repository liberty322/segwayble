/// Device registry — matches BLE names to device configs.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

import 'device_config.dart';

/// Entry from registry.json.
class DeviceEntry {
  final int serverId;
  final String name;
  final String model;
  final String hardwareId;

  const DeviceEntry({
    required this.serverId,
    required this.name,
    required this.model,
    required this.hardwareId,
  });

  factory DeviceEntry.fromJson(Map<String, dynamic> json) {
    return DeviceEntry(
      serverId: json['serverId'] as int,
      name: json['name'] as String? ?? '',
      model: json['model'] as String? ?? '',
      hardwareId: json['hardwareId'] as String? ?? '',
    );
  }

  String get displayName => name.isNotEmpty ? name : 'Device $serverId';
}

/// Global device registry, loaded from bundled assets.
class DeviceRegistry {
  final List<DeviceEntry> _entries;
  final Map<int, DeviceEntry> _byServerId;

  DeviceRegistry._(this._entries)
      : _byServerId = {for (final e in _entries) e.serverId: e};

  /// Load registry from assets.
  static Future<DeviceRegistry> load() async {
    try {
      final jsonStr =
          await rootBundle.loadString('assets/device_configs/registry.json');
      final list = jsonDecode(jsonStr) as List<dynamic>;
      final entries =
          list.map((e) => DeviceEntry.fromJson(e as Map<String, dynamic>)).toList();
      return DeviceRegistry._(entries);
    } catch (_) {
      return DeviceRegistry._([]);
    }
  }

  List<DeviceEntry> get allDevices => _entries;

  DeviceEntry? getByServerId(int serverId) => _byServerId[serverId];

  /// Heuristic match: try to identify device from BLE advertised name.
  DeviceEntry? matchDevice(String bleName) {
    final upper = bleName.toUpperCase();

    // Try exact prefix matches
    for (final entry in _entries) {
      final entryUpper = entry.name.toUpperCase();
      if (upper.startsWith(entryUpper) || entryUpper.startsWith(upper)) {
        return entry;
      }
    }

    // Try partial word matches
    for (final entry in _entries) {
      final words = entry.name.toUpperCase().split(RegExp(r'[\s/]+'));
      for (final word in words) {
        if (word.length >= 3 && upper.contains(word)) {
          return entry;
        }
      }
    }

    // Type-based heuristics
    if (upper.startsWith('S1D') || upper.contains('E125') || upper.contains('E150') || upper.contains('E250')) {
      // Motor/moped type — find first motor entry
      return _entries.where((e) => e.model == 'motor').firstOrNull;
    }
    if (upper.startsWith('NB-')) {
      // Ninebot scooter prefix
      return _entries.where((e) => e.model == 'scooter').firstOrNull;
    }

    return null;
  }

  /// Load the full DeviceConfig for an entry.
  Future<DeviceConfig?> loadConfig(DeviceEntry entry) {
    return loadDeviceConfig(
      entry.serverId,
      name: entry.name,
      model: entry.model,
      hardwareId: entry.hardwareId,
    );
  }
}
