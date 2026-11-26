/// QR payload encoding/decoding for device credentials.
///
/// Format:
///   `segway://credentials?sn={serial}&pwd={hex32}&ident={hex32}`
///
/// `sn` is optional (lets the scanner pre-associate the creds to a named
/// device). `pwd` is required, `ident` is optional (writes need it;
/// read-only monitoring works without). Hex values are lower- or
/// upper-case, 32 chars each.
library;

import 'dart:typed_data';

class CredentialPayload {
  final String? serialNumber;
  final Uint8List password;
  final Uint8List? commandIdent;

  const CredentialPayload({
    required this.password,
    this.serialNumber,
    this.commandIdent,
  });

  static Uint8List? _parseHex(String? hex) {
    if (hex == null) return null;
    final clean = hex.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (clean.length != 32) return null;
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(clean)) return null;
    final bytes = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      bytes[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  /// Parse a QR payload. Returns null on malformed input.
  static CredentialPayload? parse(String raw) {
    final Uri uri;
    try {
      uri = Uri.parse(raw.trim());
    } catch (_) {
      return null;
    }
    if (uri.scheme.toLowerCase() != 'segway') return null;
    if (uri.host.toLowerCase() != 'credentials') return null;

    final pwd = _parseHex(uri.queryParameters['pwd']);
    if (pwd == null) return null;

    Uint8List? ident;
    final rawIdent = uri.queryParameters['ident'];
    if (rawIdent != null) {
      // Present but malformed → reject the whole payload so we don't end
      // up with a password-only setup the user thought included writes.
      ident = _parseHex(rawIdent);
      if (ident == null) return null;
    }

    return CredentialPayload(
      password: pwd,
      commandIdent: ident,
      serialNumber: uri.queryParameters['sn'],
    );
  }

  String encode() {
    final qp = <String, String>{
      'pwd': password
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
    };
    if (commandIdent != null) {
      qp['ident'] = commandIdent!
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
    }
    if (serialNumber != null && serialNumber!.isNotEmpty) {
      qp['sn'] = serialNumber!;
    }
    final uri = Uri(scheme: 'segway', host: 'credentials', queryParameters: qp);
    return uri.toString();
  }
}
