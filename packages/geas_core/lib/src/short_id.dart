import 'dart:math';

/// No id matches the input.
class UnknownIdException implements Exception {
  const UnknownIdException(this.input);

  final String input;

  @override
  String toString() => 'No task matches "$input".';
}

/// Several ids match the input.
class AmbiguousIdException implements Exception {
  const AmbiguousIdException(this.input, this.matches);

  final String input;
  final List<String> matches;

  @override
  String toString() =>
      '"$input" matches ${matches.length} tasks: ${matches.join(', ')}.';
}

/// The shortest unique suffix of each id, at least [minLength] characters.
///
/// Suffixes, not prefixes: a ULID starts with its timestamp, so tasks created
/// together share leading characters, while the end is random. Matching is
/// case-insensitive.
Map<String, String> shortIds(Iterable<String> ids, {int minLength = 4}) {
  final sorted = ids.toSet().toList()
    ..sort((a, b) => _reversed(a).compareTo(_reversed(b)));
  final result = <String, String>{};
  for (var i = 0; i < sorted.length; i++) {
    final id = sorted[i];
    var shared = 0;
    if (i > 0) shared = _commonSuffix(id, sorted[i - 1]);
    if (i < sorted.length - 1) {
      final next = _commonSuffix(id, sorted[i + 1]);
      if (next > shared) shared = next;
    }
    final length = min(max(shared + 1, minLength), id.length);
    result[id] = id.substring(id.length - length);
  }
  return result;
}

/// The id that [input] names: the full id, or a suffix of exactly one id.
///
/// Throws [UnknownIdException] or [AmbiguousIdException].
String resolveId(String input, Iterable<String> ids) {
  final needle = input.trim().toUpperCase();
  if (needle.isEmpty) throw UnknownIdException(input);
  final matches = <String>[];
  for (final id in ids.toSet()) {
    final upper = id.toUpperCase();
    if (upper == needle) return id;
    if (upper.endsWith(needle)) matches.add(id);
  }
  if (matches.isEmpty) throw UnknownIdException(input);
  if (matches.length > 1) throw AmbiguousIdException(input, matches..sort());
  return matches.single;
}

String _reversed(String s) => s.toUpperCase().split('').reversed.join();

int _commonSuffix(String a, String b) {
  final x = a.toUpperCase(), y = b.toUpperCase();
  var n = 0;
  while (n < x.length &&
      n < y.length &&
      x[x.length - 1 - n] == y[y.length - 1 - n]) {
    n++;
  }
  return n;
}
