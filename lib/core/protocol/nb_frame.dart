/// Parsed Ninebot frame (after decryption).
library;

import 'dart:typed_data';

class NbFrame {
  /// LEN field (data bytes count).
  final int length;

  /// Source board (byte 3 in response).
  final int boardId;

  /// Command byte.
  final int cmd;

  /// Index / status byte.
  final int index;

  /// Payload data.
  final Uint8List data;

  const NbFrame({
    required this.length,
    required this.boardId,
    required this.cmd,
    required this.index,
    required this.data,
  });

  /// Read a uint16 little-endian from data at offset.
  int readU16([int offset = 0]) {
    if (data.length < offset + 2) return 0;
    return data[offset] | (data[offset + 1] << 8);
  }

  /// Read a uint32 little-endian from data at offset.
  int readU32([int offset = 0]) {
    if (data.length < offset + 4) return 0;
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  /// Read data as ASCII string.
  String readAscii([int? maxLen]) {
    final len = maxLen != null && maxLen < data.length ? maxLen : data.length;
    return String.fromCharCodes(data.sublist(0, len)).replaceAll('\x00', '');
  }

  @override
  String toString() =>
      'NbFrame(board=0x${boardId.toRadixString(16)}, cmd=0x${cmd.toRadixString(16)}, '
      'idx=0x${index.toRadixString(16)}, data=${_hex(data)})';

  static String _hex(Uint8List d) =>
      d.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}
