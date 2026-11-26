/// Device command configuration parsed from device_commands.json.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

/// A single BLE command definition from device_commands.json.
class DeviceCommand {
  final String name;
  final String? module;
  final String? ops; // "read", "write", "writeNR"
  final int? sIndex;
  final int? sData;
  final int? sCmd;
  final dynamic sValue; // int, String ("$ident"), or null
  final int? rIndex;
  final int? timeout;

  const DeviceCommand({
    required this.name,
    this.module,
    this.ops,
    this.sIndex,
    this.sData,
    this.sCmd,
    this.sValue,
    this.rIndex,
    this.timeout,
  });

  factory DeviceCommand.fromJson(Map<String, dynamic> json) {
    return DeviceCommand(
      name: json['name'] as String? ?? '',
      module: json['module'] as String?,
      ops: json['ops'] as String?,
      sIndex: json['s_index'] as int?,
      sData: json['s_data'] as int?,
      sCmd: json['s_cmd'] as int?,
      sValue: json['s_value'],
      rIndex: json['r_index'] as int?,
      timeout: json['timeout'] as int?,
    );
  }

  bool get requiresIdent => sValue == r'$ident';
}

/// Full device configuration for a specific vehicle type.
class DeviceConfig {
  final int serverId;
  final String name;
  final String model;
  final String hardwareId;
  final Map<String, int> moduleToBoard;
  final Map<String, DeviceCommand> commands;
  final int defaultTimeout;

  const DeviceConfig({
    required this.serverId,
    required this.name,
    required this.model,
    required this.hardwareId,
    required this.moduleToBoard,
    required this.commands,
    this.defaultTimeout = 1000,
  });

  /// Resolve a module name ("dis", "mcu", "ble") to a board ID.
  int? boardForModule(String module) => moduleToBoard[module.toLowerCase()];

  /// Get a command by name.
  DeviceCommand? command(String name) => commands[name];

  /// Build Uint8List payload for a command that uses $ident.
  Uint8List? identPayload(String ident) {
    if (ident.isEmpty) return null;
    return Uint8List.fromList(utf8.encode(ident));
  }
}

/// Parse a device_commands.json into a DeviceConfig.
DeviceConfig parseDeviceConfig({
  required int serverId,
  required String name,
  required String model,
  required String hardwareId,
  required Map<String, dynamic> json,
  Map<String, int>? moduleMapping,
}) {
  final commandsList = json['commands'] as List<dynamic>? ?? [];
  final defaults = json['defaultConfigs'] as Map<String, dynamic>? ?? {};
  final defaultTimeout = defaults['timeout'] as int? ?? 1000;

  final commands = <String, DeviceCommand>{};
  for (final cmdJson in commandsList) {
    final cmd = DeviceCommand.fromJson(cmdJson as Map<String, dynamic>);
    if (cmd.name.isNotEmpty) {
      commands[cmd.name] = cmd;
    }
  }

  // Default module→board mapping (can be overridden by config)
  final moduleToBoard = <String, int>{
    'dis': 0x01,
    'mcu': 0x02,
    'ble': 0x04,
    'bms3': 0x05,
    'bms2': 0x06,
    'bms1': 0x07,
    'ecu': 0x09,
    'hep': 0x11,
    'tft': 0x23,
  };

  if (moduleMapping != null) {
    moduleToBoard.addAll(moduleMapping);
  }

  return DeviceConfig(
    serverId: serverId,
    name: name,
    model: model,
    hardwareId: hardwareId,
    moduleToBoard: moduleToBoard,
    commands: commands,
    defaultTimeout: defaultTimeout,
  );
}

/// Load a device config from bundled assets.
Future<DeviceConfig?> loadDeviceConfig(int serverId,
    {required String name,
    required String model,
    required String hardwareId,
    Map<String, int>? moduleMapping}) async {
  try {
    final jsonStr = await rootBundle
        .loadString('assets/device_configs/$serverId.json');
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    return parseDeviceConfig(
      serverId: serverId,
      name: name,
      model: model,
      hardwareId: hardwareId,
      json: json,
      moduleMapping: moduleMapping,
    );
  } catch (_) {
    return null;
  }
}
