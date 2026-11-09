import 'due.dart';
import 'local_date.dart';

const _weekdays = {
  'mon': DateTime.monday,
  'monday': DateTime.monday,
  'tue': DateTime.tuesday,
  'tues': DateTime.tuesday,
  'tuesday': DateTime.tuesday,
  'wed': DateTime.wednesday,
  'wednesday': DateTime.wednesday,
  'thu': DateTime.thursday,
  'thur': DateTime.thursday,
  'thurs': DateTime.thursday,
  'thursday': DateTime.thursday,
  'fri': DateTime.friday,
  'friday': DateTime.friday,
  'sat': DateTime.saturday,
  'saturday': DateTime.saturday,
  'sun': DateTime.sunday,
  'sunday': DateTime.sunday,
};

final _time24 = RegExp(r'^(\d{1,2}):(\d{2})$');
final _time12 = RegExp(r'^(\d{1,2})(?::(\d{2}))?(am|pm)$');

/// Parses a due date as people type it, relative to [now]:
///
/// - a day: `today`, `tomorrow`, a weekday (`fri`, `friday`) meaning the
///   next one after today, or `YYYY-MM-DD`
/// - optionally a time: `17:00`, `5pm` or `5:30pm`
///
/// A time alone means today. A time is stored with the device's offset at
/// that moment, so other devices see the same instant. Throws
/// [FormatException] for anything else.
Due parseDueInput(String text, {required DateTime now}) {
  final words = text.trim().toLowerCase().split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  if (words.isEmpty || words.length > 2) throw _invalid(text);

  final today = LocalDate.of(now.toLocal());
  final time = words.length == 2 ? _parseTime(words[1]) : _parseTime(words[0]);
  final LocalDate date;
  if (words.length == 1 && time != null) {
    date = today;
  } else {
    if (words.length == 2 && time == null) throw _invalid(text);
    date = _parseDay(words[0], today) ?? (throw _invalid(text));
  }
  if (time == null) return Due.date(date);

  final (hour, minute) = time;
  final local = DateTime(date.year, date.month, date.day, hour, minute);
  return Due.at(date, hour, minute, offset: local.timeZoneOffset);
}

LocalDate? _parseDay(String word, LocalDate today) {
  switch (word) {
    case 'today' || 'tod':
      return today;
    case 'tomorrow' || 'tom' || 'tmr':
      return today.addDays(1);
  }
  final weekday = _weekdays[word];
  if (weekday != null) {
    final current = DateTime.utc(today.year, today.month, today.day).weekday;
    final ahead = (weekday - current + 6) % 7 + 1;
    return today.addDays(ahead);
  }
  try {
    return LocalDate.parse(word);
  } on FormatException {
    return null;
  }
}

(int, int)? _parseTime(String word) {
  final m24 = _time24.firstMatch(word);
  if (m24 != null) {
    final hour = int.parse(m24[1]!), minute = int.parse(m24[2]!);
    if (hour > 23 || minute > 59) return null;
    return (hour, minute);
  }
  final m12 = _time12.firstMatch(word);
  if (m12 != null) {
    final hour = int.parse(m12[1]!), minute = int.parse(m12[2] ?? '0');
    if (hour < 1 || hour > 12 || minute > 59) return null;
    return (hour % 12 + (m12[3] == 'pm' ? 12 : 0), minute);
  }
  return null;
}

FormatException _invalid(String text) => FormatException(
      'Can\'t read the due date "$text". Use today, tomorrow, a weekday or '
      'YYYY-MM-DD, optionally followed by a time like 17:00 or 5pm.',
    );
