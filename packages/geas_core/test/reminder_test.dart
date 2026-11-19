import 'package:geas_core/geas_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 11, 18, 12);
  const today = LocalDate(2026, 11, 18);
  Task task(String title, Due? due) =>
      Task.create(title: title, now: now, due: due);

  test('tasks are announced at their time, or at 9 on their day', () {
    final timed = task(
        'Call the dentist', Due.at(today, 17, 0, offset: now.timeZoneOffset));
    final dated = task('Renew registration', Due.date(today.addDays(2)));
    final reminders = upcomingReminders(
      tasks: [dated, timed, task('No date', null)],
      trackers: const [],
      now: now,
    );
    expect(reminders.map((r) => r.title),
        ['Call the dentist', 'Renew registration']);
    expect(reminders[0].at.toLocal(), DateTime(2026, 11, 18, 17));
    expect(reminders[0].body, 'Due at 17:00');
    expect(reminders[0].key, 'task:${timed.id}');
    expect(reminders[1].at, DateTime(2026, 11, 20, 9));
    expect(reminders[1].body, 'Due 2026-11-20');
  });

  test('nothing past, finished or already due is announced', () {
    final reminders = upcomingReminders(
      tasks: [
        task('Due this morning', const Due.date(today)),
        task('Overdue', Due.date(today.addDays(-1))),
        task('Done', Due.date(today.addDays(1))).complete(now),
        task('Tomorrow', Due.date(today.addDays(1))),
      ],
      trackers: const [],
      now: now,
    );
    expect(reminders.single.title, 'Tomorrow');

    // Before 9, today's is still to come.
    final early = upcomingReminders(
      tasks: [task('Due this morning', const Due.date(today))],
      trackers: const [],
      now: DateTime(2026, 11, 18, 7),
    );
    expect(early.single.body, 'Due today');
  });

  test('trackers are announced when the next one is due', () {
    final sensor = newTracker('CGM sensor', const [],
            kind: TrackerKind.sensor, every: const Duration(days: 10))
        .log(DateTime(2026, 11, 14, 9));
    final met =
        newTracker('Metformin', [sensor], every: const Duration(hours: 12))
            .log(DateTime(2026, 11, 18, 8));
    final overdue =
        newTracker('Vitamin D', [sensor, met], every: const Duration(days: 1))
            .log(DateTime(2026, 11, 16, 8));
    final untimed = newTracker('Ibuprofen', const []).log(now);
    final reminders = upcomingReminders(
      tasks: const [],
      trackers: [sensor, met, overdue, untimed],
      now: now,
    );
    expect(reminders.map((r) => (r.title, r.body)), [
      ('Metformin', 'Time to take it'),
      ('CGM sensor', 'Time to replace it'),
    ]);
    expect(reminders.first.at.toLocal(), DateTime(2026, 11, 18, 20));
    expect(reminders.last.at.toLocal(), DateTime(2026, 11, 24, 9));
  });

  test('ids are stable, small and differ by key', () {
    final a = Reminder(key: 'task:A', title: '', body: '', at: now);
    final b = Reminder(key: 'task:B', title: 'x', body: 'y', at: now);
    expect(a.id, Reminder(key: 'task:A', title: 'z', body: '', at: now).id);
    expect(a.id, isNot(b.id));
    expect(a.id, inInclusiveRange(0, 0x7fffffff));
  });

  test('only the soonest are kept', () {
    final reminders = upcomingReminders(
      tasks: [
        for (var day = 30; day > 0; day--)
          task('Task $day', Due.date(today.addDays(day))),
      ],
      trackers: const [],
      now: now,
      limit: 5,
    );
    expect(reminders.map((r) => r.title),
        ['Task 1', 'Task 2', 'Task 3', 'Task 4', 'Task 5']);
  });
}
