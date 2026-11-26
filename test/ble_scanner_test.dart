import 'package:app/core/ble/ble_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isSegwayName()', () {
    test('S1D prefix matches', () {
      expect(isSegwayName('S1DXXXXXXXXX01'), isTrue);
      expect(isSegwayName('S1D-test'), isTrue);
    });

    test('NB- prefix matches', () {
      expect(isSegwayName('NB-S1234'), isTrue);
      expect(isSegwayName('NB-something'), isTrue);
    });

    test('NINEBOT anywhere matches', () {
      expect(isSegwayName('Ninebot-ES2'), isTrue);
      expect(isSegwayName('My Ninebot'), isTrue);
    });

    test('SEGWAY anywhere matches', () {
      expect(isSegwayName('Segway E125S'), isTrue);
      expect(isSegwayName('My Segway'), isTrue);
    });

    test('ZING prefix matches', () {
      expect(isSegwayName('ZING-1234'), isTrue);
      expect(isSegwayName('Zing E10'), isTrue);
    });

    test('SGW prefix matches', () {
      expect(isSegwayName('SGW-Ninebot'), isTrue);
      expect(isSegwayName('sgw-test'), isTrue);
    });

    test('case insensitive', () {
      expect(isSegwayName('s1dxxxxxxxxx01'), isTrue);
      expect(isSegwayName('nb-test'), isTrue);
      expect(isSegwayName('ninebot'), isTrue);
      expect(isSegwayName('segway'), isTrue);
      expect(isSegwayName('zing'), isTrue);
      expect(isSegwayName('sgw'), isTrue);
    });

    test('rejects non-Segway names', () {
      expect(isSegwayName('iPhone'), isFalse);
      expect(isSegwayName('AirPods Pro'), isFalse);
      expect(isSegwayName('Samsung Galaxy'), isFalse);
      expect(isSegwayName('Xiaomi'), isFalse);
      expect(isSegwayName('JBL Speaker'), isFalse);
    });

    test('rejects empty string', () {
      expect(isSegwayName(''), isFalse);
    });

    test('rejects similar but not matching names', () {
      expect(isSegwayName('NINE'), isFalse);
      expect(isSegwayName('SEG'), isFalse);
      expect(isSegwayName('NB'), isFalse); // needs NB- not just NB
      expect(isSegwayName('S1'), isFalse); // needs S1D not just S1
    });
  });
}
