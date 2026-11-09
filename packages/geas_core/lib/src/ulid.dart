import 'dart:math';

const _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
final _secureRandom = Random.secure();
final _ulidPattern = RegExp(r'^[0-7][0-9A-HJKMNP-TV-Z]{25}$');

/// A new ULID: 10 characters of millisecond timestamp, then 16 of
/// randomness, in Crockford base32. IDs created later sort later.
String newUlid({DateTime? now, Random? random}) {
  final rng = random ?? _secureRandom;
  var time = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final chars = List.filled(26, '0');
  for (var i = 9; i >= 0; i--) {
    chars[i] = _crockford[time % 32];
    time ~/= 32;
  }
  for (var i = 10; i < 26; i++) {
    chars[i] = _crockford[rng.nextInt(32)];
  }
  return chars.join();
}

/// Whether [text] is a canonical (uppercase) ULID.
bool isUlid(String text) => _ulidPattern.hasMatch(text);
