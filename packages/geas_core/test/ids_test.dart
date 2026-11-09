import 'dart:math';

import 'package:geas_core/geas_core.dart';
import 'package:test/test.dart';

void main() {
  group('newUlid', () {
    test('is a valid ULID', () {
      for (var i = 0; i < 100; i++) {
        expect(isUlid(newUlid()), isTrue);
      }
    });

    test('encodes the timestamp in the first 10 characters', () {
      final now = DateTime.utc(2026, 11, 8, 23, 41, 2);
      final a = newUlid(now: now, random: Random(1));
      final b = newUlid(now: now, random: Random(2));
      expect(a.substring(0, 10), b.substring(0, 10));
      expect(a, isNot(b));
    });

    test('later ids sort later', () {
      final earlier = newUlid(now: DateTime.utc(2026, 11, 8));
      final later = newUlid(now: DateTime.utc(2026, 11, 9));
      expect(earlier.compareTo(later), lessThan(0));
    });

    test('isUlid rejects other strings', () {
      expect(isUlid('01JC8ZQ4R7ME2X5Y9V3T6N0B4K'), isTrue);
      expect(isUlid('01jc8zq4r7me2x5y9v3t6n0b4k'), isFalse);
      expect(isUlid('01JC8ZQ4R7ME2X5Y9V3T6N0B4'), isFalse);
      expect(isUlid('01JC8ZQ4R7ME2X5Y9V3T6N0BIL'), isFalse);
      expect(isUlid('81JC8ZQ4R7ME2X5Y9V3T6N0B4K'), isFalse);
    });
  });

  group('shortIds', () {
    test('uses minLength when the tails differ', () {
      final ids = ['01JC8ZQ4R7ME2X5Y9V3T6N0B4K', '01JC8ZQ4R7ME2X5Y9V3T6NWXYZ'];
      expect(shortIds(ids), {
        ids[0]: '0B4K',
        ids[1]: 'WXYZ',
      });
    });

    test('grows past a shared tail', () {
      final ids = ['01JC8ZQ4R7ME2X5Y9V3TAAB4K0', '01JC8ZQ4R7ME2X5Y9V3TCCB4K0'];
      expect(shortIds(ids), {
        ids[0]: 'AB4K0',
        ids[1]: 'CB4K0',
      });
    });

    test('every short id resolves back to its id', () {
      final rng = Random(7);
      final ids = [for (var i = 0; i < 500; i++) newUlid(random: rng)];
      final shorts = shortIds(ids);
      for (final id in ids) {
        expect(resolveId(shorts[id]!, ids), id);
      }
    });

    test('a short id is never longer than its id', () {
      expect(shortIds(['ab']), {'ab': 'ab'});
    });
  });

  group('resolveId', () {
    final ids = ['01JC8ZQ4R7ME2X5Y9V3T6N0B4K', '01JC8ZQ4R7ME2X5Y9V3T6NXB4K'];

    test('accepts a full id', () {
      expect(resolveId(ids[0], ids), ids[0]);
    });

    test('accepts a unique suffix, in any case', () {
      expect(resolveId('0b4k', ids), ids[0]);
    });

    test('rejects an ambiguous suffix', () {
      expect(
        () => resolveId('B4K', ids),
        throwsA(isA<AmbiguousIdException>()
            .having((e) => e.matches, 'matches', ids)),
      );
    });

    test('rejects an unknown or empty input', () {
      expect(() => resolveId('ZZZZ', ids), throwsA(isA<UnknownIdException>()));
      expect(() => resolveId(' ', ids), throwsA(isA<UnknownIdException>()));
    });
  });
}
