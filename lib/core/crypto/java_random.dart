/// Java LCG PRNG (java.util.Random) + password generation.
///
/// Port of the JavaRandom class from nb_crypto.py.
/// Used for SET_PWD phase password generation.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;

const int _javaMask = (1 << 48) - 1;
const int _javaMult = 0x5DEECE66D;
const int _javaAdd = 0xB;

/// Reimplements java.util.Random (48-bit LCG).
class JavaRandom {
  int _seed;

  JavaRandom(int seed)
      : _seed = (seed ^ _javaMult) & _javaMask;

  int _next(int bits) {
    _seed = (_seed * _javaMult + _javaAdd) & _javaMask;
    return _seed >> (48 - bits);
  }

  int nextInt() => _next(32);

  /// Generate n random bytes (matches java.util.Random.nextBytes).
  Uint8List nextBytes(int n) {
    final out = Uint8List(n);
    var i = 0;
    while (i < n) {
      final rnd = nextInt();
      final count = (n - i) < 4 ? (n - i) : 4;
      for (var j = 0; j < count; j++) {
        out[i] = (rnd >> (8 * j)) & 0xFF;
        i++;
      }
    }
    return out;
  }
}

/// Truncate to signed 32-bit Java int.
int _javaInt(int x) {
  x = x & 0xFFFFFFFF;
  return x >= 0x80000000 ? x - 0x100000000 : x;
}

/// Truncate to signed 64-bit Java long.
int _javaLong(int x) {
  // Dart ints are 64-bit, but we need to handle overflow like Java
  x = x.toSigned(64);
  return x;
}

/// Generate 16-byte session password.
///
/// Matches AbstractCryptoPwdProvider.getRandomData(16, auth):
///   seed = currentTimeMillis + sum(auth[i] << ((i%8)*8))
///   random_bytes = new Random(seed).nextBytes(16)
///   return SHA256(random_bytes)[:16]
///
/// Java uses int (32-bit) shifts, so shifts >= 32 wrap via & 31.
Uint8List generatePassword(Uint8List auth, {int? timeMs}) {
  timeMs ??= DateTime.now().millisecondsSinceEpoch;

  // Compute seed contribution from auth
  int j = 0;
  for (var i = 0; i < auth.length; i++) {
    // Java signed byte
    final sb = auth[i] < 128 ? auth[i] : auth[i] - 256;
    final shift = (i % 8) * 8;
    // Java int shift: only lower 5 bits of shift used for int operands
    final val = _javaInt(sb << (shift & 31));
    j = _javaLong(j + val);
  }

  final seed = _javaLong(timeMs + j);
  final rng = JavaRandom(seed);
  final randomBytes = rng.nextBytes(16);
  final sha = hash.sha256.convert(randomBytes);
  return Uint8List.fromList(sha.bytes.sublist(0, 16));
}
