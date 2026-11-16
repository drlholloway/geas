import 'due_input.dart';
import 'local_date.dart';
import 'tracker.dart';

/// How often a tracker has been logged, as of a moment.
class TrackerStats {
  const TrackerStats._({
    required this.count,
    required this.first,
    required this.last,
    required this.sinceLast,
    required this.today,
    required this.week,
    required this.month,
    required this.perDayWeek,
    required this.perDayMonth,
    required this.averageGap,
    required this.nextDue,
  });

  /// The numbers for [tracker] at [now]. Days are the device's.
  factory TrackerStats.of(Tracker tracker, DateTime now, {int gaps = 10}) {
    final entries = tracker.entries;
    final today = LocalDate.of(now.toLocal());
    int within(int days) => entries.where((e) {
          final age = _daysBetween(LocalDate.of(e.at.toLocal()), today);
          return age >= 0 && age < days;
        }).length;
    final first = entries.firstOrNull?.at, last = entries.lastOrNull?.at;
    // A tracker started three days ago averages over three days, not seven.
    final tracked = first == null
        ? 0
        : _daysBetween(LocalDate.of(first.toLocal()), today) + 1;
    double? perDay(int days) =>
        tracked < 1 ? null : within(days) / (tracked < days ? tracked : days);

    Duration? averageGap;
    if (entries.length > 1) {
      final from = entries.length - 1 - gaps;
      final start = entries[from < 0 ? 0 : from].at;
      final n = from < 0 ? entries.length - 1 : gaps;
      averageGap = last!.difference(start) ~/ n;
    }
    final every = tracker.every;
    return TrackerStats._(
      count: entries.length,
      first: first,
      last: last,
      sinceLast: last == null ? null : now.difference(last),
      today: within(1),
      week: within(7),
      month: within(30),
      perDayWeek: perDay(7),
      perDayMonth: perDay(30),
      averageGap: averageGap,
      nextDue: last == null || every == null ? null : last.add(every),
    );
  }

  /// Times logged, ever.
  final int count;

  /// The first and latest times, or null if there are none.
  final DateTime? first, last;

  /// How long ago [last] was.
  final Duration? sinceLast;

  /// Times logged today, and in the 7 and 30 days ending today.
  final int today, week, month;

  /// Times a day over those 7 and 30 days, or over the days since [first]
  /// if that's fewer. Null with nothing logged.
  final double? perDayWeek, perDayMonth;

  /// The average time between one and the next, over the latest few. Null
  /// with fewer than two logged.
  final Duration? averageGap;

  /// When the next one is due: [last] plus the tracker's `every`.
  final DateTime? nextDue;
}

/// Times [tracker] was logged on each of the [days] days ending today,
/// oldest first.
List<int> dailyCounts(Tracker tracker, DateTime now, {int days = 14}) {
  final today = LocalDate.of(now.toLocal());
  final counts = List.filled(days, 0);
  for (final entry in tracker.entries) {
    final age = _daysBetween(LocalDate.of(entry.at.toLocal()), today);
    if (age >= 0 && age < days) counts[days - 1 - age]++;
  }
  return counts;
}

/// Each entry of [tracker], newest first, with how long after the one
/// before it (null for the first).
List<({TrackerEntry entry, Duration? gap})> entryGaps(Tracker tracker) {
  final entries = tracker.entries;
  return [
    for (var i = entries.length - 1; i >= 0; i--)
      (
        entry: entries[i],
        gap: i == 0 ? null : entries[i].at.difference(entries[i - 1].at),
      ),
  ];
}

/// [span] in words: `25 min`, `4 h`, `11 h 30 min`, `1 day`, `9.8 days`.
String spanLabel(Duration span) {
  final minutes = span.inMinutes.abs();
  if (minutes < 60) return '$minutes min';
  if (minutes < 24 * 60) {
    final rest = minutes % 60;
    return rest == 0 ? '${minutes ~/ 60} h' : '${minutes ~/ 60} h $rest min';
  }
  final days = oneDecimal(minutes / (24 * 60));
  return '$days ${days == '1' ? 'day' : 'days'}';
}

/// [value] to one decimal place, without a trailing `.0`.
String oneDecimal(double value) {
  final text = value.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// Where a sensor-like tracker is in its life at [now], as `day 5 of 10`
/// (the day it was replaced is day 1), or null without an `every` of whole
/// days or anything logged.
String? wearDay(Tracker tracker, DateTime now) {
  final every = tracker.every, last = tracker.entries.lastOrNull?.at;
  if (every == null || last == null || every.inHours % 24 != 0) return null;
  final day =
      _daysBetween(LocalDate.of(last.toLocal()), LocalDate.of(now.toLocal())) +
          1;
  return 'day $day of ${every.inDays}';
}

/// Parses when something was logged, as people type it, relative to [now]:
/// a time today (`8am`, `08:15`), `yesterday 9pm`, or `YYYY-MM-DD HH:MM`.
/// Throws [FormatException] for anything else, or a time in the future.
DateTime parseLogTime(String text, {required DateTime now}) {
  final words = text.trim().toLowerCase().split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  FormatException invalid() => FormatException(
        'Can\'t read the time "$text". Use a time like 8am or 08:15, '
        'optionally after yesterday or YYYY-MM-DD.',
      );
  if (words.isEmpty || words.length > 2) throw invalid();
  final local = now.toLocal();
  var day = DateTime(local.year, local.month, local.day);
  if (words.length == 2) {
    if (words.first == 'yesterday') {
      day = DateTime(local.year, local.month, local.day - 1);
    } else if (words.first != 'today') {
      try {
        final date = LocalDate.parse(words.first);
        day = DateTime(date.year, date.month, date.day);
      } on FormatException {
        throw invalid();
      }
    }
  }
  final time = parseClockTime(words.last) ?? (throw invalid());
  final at = DateTime(day.year, day.month, day.day, time.$1, time.$2);
  if (at.isAfter(now.add(const Duration(minutes: 1)))) {
    throw FormatException('"$text" hasn\'t happened yet.');
  }
  return at;
}

int _daysBetween(LocalDate a, LocalDate b) =>
    DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;
