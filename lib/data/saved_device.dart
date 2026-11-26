/// Saved BLE device for quick reconnect.
library;

import 'dart:convert';
import 'dart:typed_data';

class SavedDevice {
  final String mac;
  final String name;
  final int lastConnectedMs;
  final String? serialNumber;
  final Uint8List? password;
  final Uint8List? auth; // cached auth from last handshake (session reuse)
  final Uint8List? sn; // cached SN bytes from last handshake
  final int? counter; // last crypto counter for session reuse

  /// 16-byte device-authorization ident. Payload for cmd=0x64 vehicle
  /// actions (openAcc / closeAcc / openTrunk). Issued by the Segway cloud
  /// at pairing and persisted on-device for offline use — we load it the
  /// same way we load [password]: a hex string pasted from the iPhone
  /// backup UserDefaults key `{serialNumber}_ident`.
  final Uint8List? commandIdent;

  const SavedDevice({
    required this.mac,
    required this.name,
    required this.lastConnectedMs,
    this.serialNumber,
    this.password,
    this.auth,
    this.sn,
    this.counter,
    this.commandIdent,
  });

  Map<String, Object?> toMap() => {
        'mac': mac,
        'name': name,
        'last_connected': lastConnectedMs,
        'serial_number': serialNumber,
        'password': password != null ? base64Encode(password!) : null,
        'auth': auth != null ? base64Encode(auth!) : null,
        'sn': sn != null ? base64Encode(sn!) : null,
        'counter': counter,
        'command_ident':
            commandIdent != null ? base64Encode(commandIdent!) : null,
      };

  factory SavedDevice.fromMap(Map<String, Object?> map) => SavedDevice(
        mac: map['mac']! as String,
        name: map['name']! as String,
        lastConnectedMs: map['last_connected']! as int,
        serialNumber: map['serial_number'] as String?,
        password: map['password'] != null
            ? Uint8List.fromList(base64Decode(map['password']! as String))
            : null,
        auth: map['auth'] != null
            ? Uint8List.fromList(base64Decode(map['auth']! as String))
            : null,
        sn: map['sn'] != null
            ? Uint8List.fromList(base64Decode(map['sn']! as String))
            : null,
        counter: map['counter'] as int?,
        commandIdent: map['command_ident'] != null
            ? Uint8List.fromList(base64Decode(map['command_ident']! as String))
            : null,
      );

  SavedDevice copyWith({
    String? name,
    int? lastConnectedMs,
    String? serialNumber,
    Uint8List? password,
    Uint8List? auth,
    Uint8List? sn,
    int? counter,
    Uint8List? commandIdent,
  }) =>
      SavedDevice(
        mac: mac,
        name: name ?? this.name,
        lastConnectedMs: lastConnectedMs ?? this.lastConnectedMs,
        serialNumber: serialNumber ?? this.serialNumber,
        password: password ?? this.password,
        auth: auth ?? this.auth,
        sn: sn ?? this.sn,
        counter: counter ?? this.counter,
        commandIdent: commandIdent ?? this.commandIdent,
      );
}
