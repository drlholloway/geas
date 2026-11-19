import 'local_date.dart';
import 'task.dart';
import 'tracker.dart';
import 'tracker_stats.dart';

/// The hour of the day, here, a task due on a date with no time is
/// announced.
const reminderHour = 9;

/// A notification to show at a moment: a task coming due, or a medication
/// or sensor due again.
class Reminder {
  const Reminder({
    required this.key,
    required this.title,
    required this.body,
    required this.at,
  });

  /// `task:<id>` or `tracker:<id>`; one reminder each.
  final String key;
  final String title;
  final String body;

  /// When to show it.
  final DateTime at;

  /// A number for [key] that stays the same from run to run, as
  /// notification systems want: 31 bits of an FNV-1a hash.
  int get id {
    var hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }

  @override
  bool operator ==(Object other) =>
      other is Reminder &&
      other.key == key &&
      other.title == title &&
      other.body == body &&
      other.at == at;

  @override
  int get hashCode => Object.hash(key, title, body, at);

  @override
  String toString() => 'Reminder($key, $at)';
}

/// The next reminders after [now], soonest first, at most [limit]:
///
/// - each open task with a due time, at that time; with only a due date, at
///   [reminderHour] that day here;
/// - each tracker with an `every`, when its next one is due.
///
/// Nothing already past is included, so an overdue task isn't announced
/// again.
List<Reminder> upcomingReminders({
  required Iterable<Task> tasks,
  required Iterable<Tracker> trackers,
  required DateTime now,
  int limit = 48,
}) {
  final today = LocalDate.of(now.toLocal());
  final reminders = <Reminder>[];
  for (final task in tasks) {
    final due = task.due;
    if (due == null || task.isCompleted) continue;
    final instant = due.instant;
    final at = instant ??
        DateTime(due.date.year, due.date.month, due.date.day, reminderHour);
    if (!at.isAfter(now)) continue;
    final local = at.toLocal();
    final time = '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    reminders.add(Reminder(
      key: 'task:${task.id}',
      title: task.title,
      body: instant == null
          ? (due.date == today ? 'Due today' : 'Due ${due.date}')
          : 'Due at $time',
      at: at,
    ));
  }
  for (final tracker in trackers) {
    final due = TrackerStats.of(tracker, now).nextDue;
    if (due == null || !due.isAfter(now)) continue;
    reminders.add(Reminder(
      key: 'tracker:${tracker.id}',
      title: tracker.name,
      body: 'Time to ${tracker.kind.action.toLowerCase()} it',
      at: due,
    ));
  }
  reminders.sort((a, b) {
    final byTime = a.at.compareTo(b.at);
    return byTime != 0 ? byTime : a.key.compareTo(b.key);
  });
  return reminders.take(limit).toList();
}
