import 'dart:convert';

import 'package:collection/collection.dart';

import 'local_date.dart';
import 'task.dart';
import 'tracker.dart';
import 'tracker_stats.dart';
import 'yaml_fields.dart';

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

/// Reminders that have been acknowledged, on any device: the optional
/// `dismissed.yaml` at the top of the data repo. For each reminder's
/// [Reminder.key] it holds the time of the latest one dismissed, so a
/// medication's next reminder isn't covered by the last one's dismissal.
class Dismissals {
  const Dismissals([this.times = const {}]);

  /// Parses `dismissed.yaml`, throwing [FormatException] if it isn't a map
  /// of timestamps.
  factory Dismissals.parse(String text) {
    if (text.trim().isEmpty) return const Dismissals();
    final map = parseYamlMap(text, 'dismissed.yaml');
    return Dismissals({
      for (final entry in map.entries)
        '${entry.key}': DateTime.tryParse('${entry.value}')?.toUtc() ??
            (throw FormatException(
                '"${entry.key}" in dismissed.yaml needs a timestamp.')),
    });
  }

  /// The time of the latest reminder dismissed, by reminder key, in UTC.
  final Map<String, DateTime> times;

  /// Whether [reminder] was dismissed: one for the same thing, at its time
  /// or later, has been.
  bool covers(Reminder reminder) {
    final dismissed = times[reminder.key];
    return dismissed != null && !dismissed.isBefore(reminder.at);
  }

  /// With the reminder for [key] at [at] dismissed. Entries more than
  /// [keep] older than [now] are dropped, so the file doesn't grow forever.
  Dismissals dismiss(
    String key,
    DateTime at, {
    required DateTime now,
    Duration keep = const Duration(days: 60),
  }) {
    final cutoff = now.subtract(keep);
    final current = times[key];
    return Dismissals({
      for (final entry in times.entries)
        if (!entry.value.isBefore(cutoff)) entry.key: entry.value,
      key: current != null && current.isAfter(at) ? current : at.toUtc(),
    });
  }

  /// [local] and [remote] together: for each reminder, the later dismissal.
  /// Two devices dismissing things never conflict.
  static Dismissals merge(Dismissals local, Dismissals remote) => Dismissals({
        ...remote.times,
        for (final entry in local.times.entries)
          if (remote.times[entry.key]?.isBefore(entry.value) ?? true)
            entry.key: entry.value,
      });

  /// The file: a line a reminder, oldest first.
  String encode() {
    final entries = times.entries.toList()
      ..sort((a, b) {
        final byTime = a.value.compareTo(b.value);
        return byTime != 0 ? byTime : a.key.compareTo(b.key);
      });
    return [
      for (final entry in entries)
        '${jsonEncode(entry.key)}: '
            '${entry.value.toUtc().toIso8601String().substring(0, 19)}Z\n',
    ].join();
  }

  @override
  bool operator ==(Object other) =>
      other is Dismissals &&
      const MapEquality<String, DateTime>().equals(other.times, times);

  @override
  int get hashCode => const MapEquality<String, DateTime>().hash(times);
}

/// Where dismissed reminders are recorded.
const dismissedPath = 'dismissed.yaml';

/// A reminder for each open task with a due date and each tracker with an
/// `every`, whenever it falls.
List<Reminder> _reminders(
  Iterable<Task> tasks,
  Iterable<Tracker> trackers,
  DateTime now,
  int dayMinutes,
) {
  final today = LocalDate.of(now.toLocal());
  final reminders = <Reminder>[];
  for (final task in tasks) {
    final due = task.due;
    if (due == null || task.isCompleted) continue;
    final instant = due.instant;
    final at = instant ??
        DateTime(due.date.year, due.date.month, due.date.day, dayMinutes ~/ 60,
            dayMinutes % 60);
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
    if (due == null) continue;
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
  return reminders;
}

/// The next reminders after [now], soonest first, at most [limit]:
///
/// - each open task with a due time, at that time; with only a due date, at
///   [dayMinutes] past midnight that day here ([reminderHour] o'clock
///   unless the device says otherwise);
/// - each tracker with an `every`, when its next one is due.
///
/// Nothing already past is included, so an overdue task isn't announced
/// again.
List<Reminder> upcomingReminders({
  required Iterable<Task> tasks,
  required Iterable<Tracker> trackers,
  required DateTime now,
  int dayMinutes = reminderHour * 60,
  int limit = 48,
}) =>
    _reminders(tasks, trackers, now, dayMinutes)
        .where((r) => r.at.isAfter(now))
        .take(limit)
        .toList();

/// The reminders whose time has come and that still stand at [now], oldest
/// first: the task is still open, or the tracker still due, and no device
/// has dismissed it. A notification for anything else can be cleared.
List<Reminder> standingReminders({
  required Iterable<Task> tasks,
  required Iterable<Tracker> trackers,
  required DateTime now,
  int dayMinutes = reminderHour * 60,
  Dismissals dismissed = const Dismissals(),
}) =>
    _reminders(tasks, trackers, now, dayMinutes)
        .where((r) => !r.at.isAfter(now) && !dismissed.covers(r))
        .toList();
