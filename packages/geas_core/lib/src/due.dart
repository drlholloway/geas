import 'local_date.dart';

/// When a task is due: a date, or a date and time.
///
/// Written as `2026-11-12`, or `2026-11-12T09:00-06:00` with a time. A time
/// with no offset is floating: 09:00 wherever the device is.
class Due {
  const Due.date(this.date)
      : hour = null,
        minute = null,
        offset = null;

  const Due.at(this.date, int this.hour, int this.minute, {this.offset});

  /// Parses the frontmatter form, throwing [FormatException] if it's invalid.
  /// Seconds are accepted and dropped.
  factory Due.parse(String text) {
    final m = _pattern.firstMatch(text.trim());
    if (m == null) {
      throw FormatException(
        'Expected YYYY-MM-DD or YYYY-MM-DDTHH:MM with an optional offset, '
        'got "$text".',
      );
    }
    final date = LocalDate.parse(m[1]!);
    if (m[2] == null) return Due.date(date);
    final hour = int.parse(m[2]!), minute = int.parse(m[3]!);
    if (hour > 23 || minute > 59) {
      throw FormatException('No such time of day in "$text".');
    }
    return Due.at(date, hour, minute, offset: _parseOffset(m[4]));
  }

  static final _pattern = RegExp(
    r'^(\d{4}-\d{2}-\d{2})'
    r'(?:[T ](\d{2}):(\d{2})(?::\d{2}(?:\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?)?$',
  );

  final LocalDate date;

  /// Null for a date-only due.
  final int? hour;
  final int? minute;

  /// Null for a date-only due or a floating time.
  final Duration? offset;

  bool get hasTime => hour != null;

  /// The moment it's due, or null for a date-only due.
  DateTime? get instant {
    if (!hasTime) return null;
    final offset = this.offset;
    if (offset == null) {
      return DateTime(date.year, date.month, date.day, hour!, minute!);
    }
    return DateTime.utc(date.year, date.month, date.day, hour!, minute!)
        .subtract(offset);
  }

  /// The date it's due in the device's time zone.
  LocalDate get localDate => hasTime ? LocalDate.of(instant!.toLocal()) : date;

  @override
  bool operator ==(Object other) =>
      other is Due &&
      other.date == date &&
      other.hour == hour &&
      other.minute == minute &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(date, hour, minute, offset);

  @override
  String toString() {
    if (!hasTime) return '$date';
    final time = '${_two(hour!)}:${_two(minute!)}';
    final offset = this.offset;
    if (offset == null) return '${date}T$time';
    if (offset == Duration.zero) return '${date}T${time}Z';
    final sign = offset.isNegative ? '-' : '+';
    final minutes = offset.inMinutes.abs();
    return '${date}T$time$sign${_two(minutes ~/ 60)}:${_two(minutes % 60)}';
  }
}

Duration? _parseOffset(String? text) {
  if (text == null) return null;
  if (text == 'Z') return Duration.zero;
  final digits = text.substring(1).replaceAll(':', '');
  final minutes =
      int.parse(digits.substring(0, 2)) * 60 + int.parse(digits.substring(2));
  return Duration(minutes: text.startsWith('-') ? -minutes : minutes);
}

String _two(int n) => n.toString().padLeft(2, '0');
