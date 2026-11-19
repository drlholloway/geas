import 'dart:math';

import 'checklist.dart';
import 'due.dart';
import 'local_date.dart';
import 'task.dart';

/// What a [Repeat] counts in.
enum RepeatUnit {
  day('d', 'day'),
  week('w', 'week'),
  month('m', 'month'),
  year('y', 'year');

  const RepeatUnit(this.letter, this.word);

  final String letter, word;
}

/// How often a task comes back once it's done: the optional `repeat` key,
/// written `daily`, `weekdays`, `weekly`, `monthly`, `yearly`, or a count
/// and a unit such as `2w` or `10d`.
class Repeat {
  const Repeat(this.count, this.unit) : weekdaysOnly = false;

  /// Monday to Friday.
  const Repeat.weekdays()
      : count = 1,
        unit = RepeatUnit.day,
        weekdaysOnly = true;

  /// Parses the file form, and `every 2 weeks` as people type it. Throws
  /// [FormatException] for anything else.
  factory Repeat.parse(String text) {
    final t = text.trim().toLowerCase().replaceFirst(RegExp(r'^every\s+'), '');
    switch (t) {
      case 'daily' || 'day':
        return const Repeat(1, RepeatUnit.day);
      case 'weekdays' || 'weekday':
        return const Repeat.weekdays();
      case 'weekly' || 'week':
        return const Repeat(1, RepeatUnit.week);
      case 'monthly' || 'month':
        return const Repeat(1, RepeatUnit.month);
      case 'yearly' || 'year' || 'annually':
        return const Repeat(1, RepeatUnit.year);
    }
    final m = _pattern.firstMatch(t);
    final count = m == null ? 0 : int.parse(m[1]!);
    if (m == null || count < 1) {
      throw FormatException(
        'Can\'t read the repeat "$text". Use daily, weekdays, weekly, '
        'monthly, yearly, or a count and unit like 2w or 10d.',
      );
    }
    return Repeat(
        count, RepeatUnit.values.firstWhere((u) => u.letter == m[2]![0]));
  }

  static final _pattern =
      RegExp(r'^(\d+)\s*(d|days?|w|weeks?|m|months?|y|years?)$');

  final int count;
  final RepeatUnit unit;
  final bool weekdaysOnly;

  /// The next date after [date].
  LocalDate after(LocalDate date) {
    if (weekdaysOnly) {
      var next = date.addDays(1);
      while (_weekday(next) > DateTime.friday) {
        next = next.addDays(1);
      }
      return next;
    }
    switch (unit) {
      case RepeatUnit.day:
        return date.addDays(count);
      case RepeatUnit.week:
        return date.addDays(7 * count);
      case RepeatUnit.month:
        return _addMonths(date, count);
      case RepeatUnit.year:
        return _addMonths(date, 12 * count);
    }
  }

  /// "Every day", "Every weekday", "Every 2 weeks".
  String get label => weekdaysOnly
      ? 'Every weekday'
      : count == 1
          ? 'Every ${unit.word}'
          : 'Every $count ${unit.word}s';

  @override
  bool operator ==(Object other) =>
      other is Repeat &&
      other.count == count &&
      other.unit == unit &&
      other.weekdaysOnly == weekdaysOnly;

  @override
  int get hashCode => Object.hash(count, unit, weekdaysOnly);

  /// The file form.
  @override
  String toString() {
    if (weekdaysOnly) return 'weekdays';
    if (count > 1) return '$count${unit.letter}';
    return switch (unit) {
      RepeatUnit.day => 'daily',
      RepeatUnit.week => 'weekly',
      RepeatUnit.month => 'monthly',
      RepeatUnit.year => 'yearly',
    };
  }
}

/// [task] finished at [now]. For a repeating task, also the task that
/// takes its place: a new one with the same title, list, tags, priority and
/// notes, its checklist unticked, due on the next date after today that the
/// repeat lands on (counted from the due date, or from today without one).
/// The finished one stops repeating, so reopening and finishing it again
/// doesn't make another.
List<Task> completeTask(Task task, DateTime now, {Random? random}) {
  final repeat = task.repeat;
  if (repeat == null || task.isCompleted) return [task.complete(now)];

  final today = LocalDate.of(now.toLocal());
  final due = task.due;
  var date = repeat.after(due?.localDate ?? today);
  while (!date.isAfter(today)) {
    date = repeat.after(date);
  }
  final Due next;
  if (due == null || !due.hasTime) {
    next = Due.date(date);
  } else {
    // The same time of day here, with the offset in force on that date.
    final at = due.instant!.toLocal();
    final local = DateTime(date.year, date.month, date.day, at.hour, at.minute);
    next = Due.at(
      date,
      at.hour,
      at.minute,
      offset: due.offset == null ? null : local.timeZoneOffset,
    );
  }

  var body = task.body;
  for (final item in parseChecklist(body)) {
    if (item.done) body = setChecklistLine(body, item.line, done: false);
  }
  return [
    task.complete(now).copyWith(repeat: null),
    Task.create(
      title: task.title,
      now: now,
      list: task.list,
      tags: task.tags,
      due: next,
      priority: task.priority,
      body: body,
      random: random,
    ).copyWith(repeat: repeat),
  ];
}

int _weekday(LocalDate date) =>
    DateTime.utc(date.year, date.month, date.day).weekday;

/// [date] moved [months] on, kept in the month it lands in: January 31
/// plus a month is the last day of February.
LocalDate _addMonths(LocalDate date, int months) {
  final first = DateTime.utc(date.year, date.month + months);
  final last = DateTime.utc(first.year, first.month + 1, 0).day;
  return LocalDate(first.year, first.month, date.day > last ? last : date.day);
}
