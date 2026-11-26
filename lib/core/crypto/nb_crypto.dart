/// Ninebot BLE Encryption2 crypto primitives.
///
/// Port of nb_crypto.py — AES-128 CTR + CBC-MAC.
/// Verified against Ghidra decompilation of nb_encrypt @ 0x169f80.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:pointycastle/export.dart';

import '../logger.dart';

/// fw_data constant (Gen2 non-SN ECB input and initial key2).
/// From libnbcrypto.so @ 0x45A80.
final Uint8List fwData = Uint8List.fromList([
  0x97, 0xCF, 0xB8, 0x02, 0x84, 0x41, 0x43, 0xDE,
  0x56, 0x00, 0x2B, 0x3B, 0x34, 0x78, 0x0A, 0x5D,
]);

// ---------------------------------------------------------------------------
// Key derivation
// ---------------------------------------------------------------------------

/// SHA-1(pad16(key1) || pad16(key2))[:16] → AES-128 key.
Uint8List deriveKey(Uint8List key1, Uint8List? key2) {
  final k1 = _pad16(key1);
  final k2 = key2 != null ? _pad16(key2) : Uint8List(16);
  final combined = Uint8List(32);
  combined.setRange(0, 16, k1);
  combined.setRange(16, 32, k2);
  final sha1 = hash.sha1.convert(combined);
  return Uint8List.fromList(sha1.bytes.sublist(0, 16));
}

Uint8List _pad16(Uint8List data) {
  final out = Uint8List(16);
  final len = data.length < 16 ? data.length : 16;
  out.setRange(0, len, data);
  return out;
}

// ---------------------------------------------------------------------------
// AES-ECB single block
// ---------------------------------------------------------------------------

Uint8List _aesEcbOne(Uint8List key, Uint8List block) {
  final cipher = ECBBlockCipher(AESEngine())
    ..init(true, KeyParameter(key));
  final out = Uint8List(16);
  cipher.processBlock(block, 0, out, 0);
  return out;
}

// ---------------------------------------------------------------------------
// Nonce / CTR block construction
// ---------------------------------------------------------------------------

/// Build the 13-byte nonce: counter_BE32[4] || auth[0:8] || 0x00.
Uint8List _buildNonce(int counter, Uint8List auth) {
  final nonce = Uint8List(13);
  final bd = ByteData.sublistView(nonce);
  bd.setUint32(0, counter & 0xFFFFFFFF, Endian.big);
  nonce.setRange(4, 12, auth, 0);
  nonce[12] = 0x00;
  return nonce;
}

/// Build A_i CTR block (16 bytes). i=0 for tag, i=1+ for data.
Uint8List _buildABlock(Uint8List nonce13, int blockI) {
  final a = Uint8List(16);
  a[0] = 0x01;
  a.setRange(1, 14, nonce13);
  a[14] = 0x00;
  a[15] = blockI & 0xFF;
  return a;
}

/// Build B_0 block for CBC-MAC (16 bytes).
Uint8List _buildB0(Uint8List nonce13, int payloadLen) {
  final b0 = Uint8List(16);
  b0[0] = 0x59;
  b0.setRange(1, 14, nonce13);
  b0[14] = 0x00;
  b0[15] = payloadLen & 0xFF;
  return b0;
}

// ---------------------------------------------------------------------------
// CBC-MAC (from Ghidra: FUN_0016a35c)
// ---------------------------------------------------------------------------

/// Compute 4-byte CBC-MAC tag over the plaintext frame.
Uint8List _cbcMac(Uint8List aesKey, Uint8List plaintext, Uint8List nonce13) {
  final payloadLen = plaintext.length - 3;

  // B0
  var x = _aesEcbOne(aesKey, _buildB0(nonce13, payloadLen));

  // Associated data: first 3 bytes, zero-padded to 16
  final aad = Uint8List(16);
  aad.setRange(0, 3, plaintext);
  x = _aesEcbOne(aesKey, _xor16(x, aad));

  // Payload blocks (plaintext[3:])
  var offset = 3;
  while (offset < plaintext.length) {
    final remaining = plaintext.length - offset;
    final chunkLen = remaining < 16 ? remaining : 16;
    final block = Uint8List(16);
    block.setRange(0, chunkLen, plaintext, offset);
    x = _aesEcbOne(aesKey, _xor16(x, block));
    offset += 16;
  }

  return Uint8List.fromList(x.sublist(0, 4));
}

Uint8List _xor16(Uint8List a, Uint8List b) {
  final out = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    out[i] = a[i] ^ b[i];
  }
  return out;
}

// ---------------------------------------------------------------------------
// CTR-mode XOR
// ---------------------------------------------------------------------------

Uint8List _ctrXor(Uint8List aesKey, Uint8List data, Uint8List nonce13,
    {int startCtr = 1}) {
  final out = Uint8List(data.length);
  var blockI = startCtr;
  var offset = 0;
  while (offset < data.length) {
    final keystream = _aesEcbOne(aesKey, _buildABlock(nonce13, blockI));
    final chunkLen = (data.length - offset) < 16 ? (data.length - offset) : 16;
    for (var j = 0; j < chunkLen; j++) {
      out[offset + j] = data[offset + j] ^ keystream[j];
    }
    offset += chunkLen;
    blockI++;
  }
  return out;
}

// ---------------------------------------------------------------------------
// NbCrypto — stateful encryption context
// ---------------------------------------------------------------------------

/// Stateful encryption context mirroring libnbcrypto.so crypto_param_t.
class NbCrypto {
  Uint8List? key1;
  Uint8List? key2;
  Uint8List auth;
  int counter;
  Uint8List ecbInput;

  NbCrypto({Uint8List? ecbInput})
      : auth = Uint8List(16),
        counter = 0,
        ecbInput = ecbInput ?? Uint8List(16);

  void setKey(Uint8List key1, Uint8List? key2) {
    this.key1 = key1;
    this.key2 = key2;
  }

  void setAuthParam(Uint8List auth) {
    this.auth = Uint8List.fromList(auth.sublist(0, auth.length < 16 ? auth.length : 16));
    if (this.auth.length < 16) {
      final padded = Uint8List(16);
      padded.setRange(0, this.auth.length, this.auth);
      this.auth = padded;
    }
  }

  /// Enable SN mode (counter starts at 1, first encrypt uses 2).
  void startSn() => counter = 1;

  void resetSn() => counter = 0;

  Uint8List get _aesKey => deriveKey(key1 ?? Uint8List(0), key2);

  // ── Encrypt ──────────────────────────────────────────────────────

  Uint8List encrypt(Uint8List plaintext) {
    final aesKey = _aesKey;
    final header = plaintext.sublist(0, 3);

    if (counter > 0) {
      talker.verbose('Crypto encrypt: mode=SN, ctr=$counter, ${plaintext.length}B');
      return _encryptSn(aesKey, plaintext, header);
    } else {
      talker.verbose('Crypto encrypt: mode=nonSN, ${plaintext.length}B');
      return _encryptNonSn(aesKey, plaintext, header);
    }
  }

  Uint8List _encryptSn(Uint8List aesKey, Uint8List plaintext, Uint8List header) {
    counter++;
    final ctr = counter;
    final nonce13 = _buildNonce(ctr, auth);

    // CBC-MAC over plaintext
    final rawTag = _cbcMac(aesKey, plaintext, nonce13);

    // CTR encrypt payload (plaintext[3:])
    final ciphertext = _ctrXor(aesKey, plaintext.sublist(3), nonce13);

    // Encrypt tag with A_0
    final a0Ks = _aesEcbOne(aesKey, _buildABlock(nonce13, 0));
    final encTag = Uint8List(4);
    for (var i = 0; i < 4; i++) {
      encTag[i] = rawTag[i] ^ a0Ks[i];
    }

    // Counter tail: big-endian uint16
    final ctrTail = Uint8List(2);
    ctrTail[0] = (ctr >> 8) & 0xFF;
    ctrTail[1] = ctr & 0xFF;

    // Assemble: header + ciphertext + encTag + ctrTail
    final result = Uint8List(header.length + ciphertext.length + 4 + 2);
    var off = 0;
    result.setRange(off, off + header.length, header);
    off += header.length;
    result.setRange(off, off + ciphertext.length, ciphertext);
    off += ciphertext.length;
    result.setRange(off, off + 4, encTag);
    off += 4;
    result.setRange(off, off + 2, ctrTail);
    return result;
  }

  Uint8List _encryptNonSn(Uint8List aesKey, Uint8List plaintext, Uint8List header) {
    final payload = plaintext.sublist(3);

    // Checksum over payload
    var sum = 0;
    for (final b in payload) {
      sum += b;
    }
    final checksum = (~sum) & 0xFFFF;

    // Static keystream: AES_ECB(key, ecbInput)
    final keystream = _aesEcbOne(aesKey, ecbInput);

    // XOR each block with the SAME keystream
    final out = Uint8List(payload.length);
    for (var offset = 0; offset < payload.length;) {
      final chunkLen = (payload.length - offset) < 16 ? (payload.length - offset) : 16;
      for (var j = 0; j < chunkLen; j++) {
        out[offset + j] = payload[offset + j] ^ keystream[j];
      }
      offset += chunkLen;
    }

    final tail = Uint8List.fromList([
      0x00, 0x00,
      checksum & 0xFF, (checksum >> 8) & 0xFF,
      0x00, 0x00,
    ]);

    final result = Uint8List(header.length + out.length + tail.length);
    result.setRange(0, header.length, header);
    result.setRange(header.length, header.length + out.length, out);
    result.setRange(header.length + out.length, result.length, tail);
    return result;
  }

  // ── Decrypt ──────────────────────────────────────────────────────

  /// Decrypt an encrypted frame.
  /// Returns (decrypted_plaintext, return_code).
  /// Return codes: 0=success, 1=MAC mismatch, 2=replay.
  (Uint8List, int) decrypt(Uint8List cipherframe) {
    final aesKey = _aesKey;
    final header = cipherframe.sublist(0, 3);

    // Extract tail (last 6 bytes)
    final tail = cipherframe.sublist(cipherframe.length - 6);
    final encryptedBody = cipherframe.sublist(3, cipherframe.length - 6);

    // Read counter from tail (big-endian uint16)
    final recvCounter = (tail[4] << 8) | tail[5];

    if (recvCounter > 0) {
      final result = _decryptSn(aesKey, header, encryptedBody, tail, recvCounter);
      talker.verbose('Crypto decrypt: mode=SN, ctr=$recvCounter, rc=${result.$2}');
      if (result.$2 == 1) talker.warning('Crypto: MAC mismatch! ctr=$recvCounter');
      return result;
    } else {
      final result = _decryptNonSn(aesKey, header, encryptedBody, tail);
      talker.verbose('Crypto decrypt: mode=nonSN, rc=${result.$2}');
      if (result.$2 == 1) talker.warning('Crypto: checksum mismatch!');
      return result;
    }
  }

  (Uint8List, int) _decryptSn(Uint8List aesKey, Uint8List header,
      Uint8List encBody, Uint8List tail, int recvCounter) {
    final nonce13 = _buildNonce(recvCounter, auth);

    // CTR decrypt payload
    final plaintextPayload = _ctrXor(aesKey, encBody, nonce13);

    // Decrypt tag with A_0
    final encTag = tail.sublist(0, 4);
    final a0Ks = _aesEcbOne(aesKey, _buildABlock(nonce13, 0));
    final recvTag = Uint8List(4);
    for (var i = 0; i < 4; i++) {
      recvTag[i] = encTag[i] ^ a0Ks[i];
    }

    // Reconstruct plaintext and verify MAC
    final plaintext = Uint8List(header.length + plaintextPayload.length);
    plaintext.setRange(0, header.length, header);
    plaintext.setRange(header.length, plaintext.length, plaintextPayload);

    final expectedTag = _cbcMac(aesKey, plaintext, nonce13);

    for (var i = 0; i < 4; i++) {
      if (recvTag[i] != expectedTag[i]) {
        return (plaintext, 1); // MAC mismatch
      }
    }

    return (plaintext, 0);
  }

  (Uint8List, int) _decryptNonSn(
      Uint8List aesKey, Uint8List header, Uint8List encBody, Uint8List tail) {
    final keystream = _aesEcbOne(aesKey, ecbInput);

    final out = Uint8List(encBody.length);
    for (var offset = 0; offset < encBody.length;) {
      final chunkLen =
          (encBody.length - offset) < 16 ? (encBody.length - offset) : 16;
      for (var j = 0; j < chunkLen; j++) {
        out[offset + j] = encBody[offset + j] ^ keystream[j];
      }
      offset += chunkLen;
    }

    final plaintext = Uint8List(header.length + out.length);
    plaintext.setRange(0, header.length, header);
    plaintext.setRange(header.length, plaintext.length, out);

    // Verify checksum
    final payload = plaintext.sublist(3);
    var sum = 0;
    for (final b in payload) {
      sum += b;
    }
    final expectedCsum = (~sum) & 0xFFFF;
    final recvCsum = tail[2] | (tail[3] << 8);
    if (expectedCsum != recvCsum) {
      return (plaintext, 1); // checksum mismatch
    }

    return (plaintext, 0);
  }
}
