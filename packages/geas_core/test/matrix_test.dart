import 'dart:convert';

import 'package:geas_core/geas_core.dart';
import 'package:geas_core/testing.dart';
import 'package:test/test.dart';

void main() {
  // Monday, November 9, 2026, at noon on this machine.
  final now = DateTime(2026, 11, 9, 12);
  final today = LocalDate.of(now);

  Task task({Due? due, Priority priority = Priority.none, String? tag}) =>
      Task.create(
        title: 't',
        now: now,
        due: due,
        priority: priority,
        tags: [if (tag != null) tag],
      );

  test('each quadrant is one priority', () {
    for (final q in Quadrant.values) {
      expect(Quadrant.of(q.priority), q);
    }
    expect(Quadrant.of(Priority.high), Quadrant.doFirst);
    expect(Quadrant.of(Priority.medium), Quadrant.schedule);
    expect(Quadrant.of(Priority.low), Quadrant.delegate);
    expect(Quadrant.of(Priority.none), Quadrant.drop);
  });

  group('dueWarning', () {
    DueWarning on(int days, {int warnDays = defaultWarnDays}) =>
        dueWarning(task(due: Due.date(today.addDays(days))), now,
            warnDays: warnDays);

    test('overdue, approaching within two days, then none', () {
      expect(on(-1), DueWarning.overdue);
      expect(on(0), DueWarning.approaching);
      expect(on(2), DueWarning.approaching);
      expect(on(3), DueWarning.none);
    });

    test('a time earlier today is overdue', () {
      final due =
          Due.at(today, 9, 0, offset: DateTime(2026, 11, 9, 9).timeZoneOffset);
      expect(dueWarning(task(due: due), now), DueWarning.overdue);
    });

    test('warnDays widens or narrows the window', () {
      expect(on(5, warnDays: 7), DueWarning.approaching);
      expect(on(1, warnDays: 0), DueWarning.none);
      expect(on(0, warnDays: 0), DueWarning.approaching);
    });

    test('undated and completed tasks have none', () {
      expect(dueWarning(task(), now), DueWarning.none);
      final done = task(due: Due.date(today.addDays(-3))).complete(now);
      expect(dueWarning(done, now), DueWarning.none);
    });
  });

  test('matrixOf sorts open tasks by priority and filters', () {
    final high = task(priority: Priority.high, due: Due.date(today));
    final medium = task(priority: Priority.medium, tag: 'pedals');
    final none = task(due: Due.date(today.addDays(4)), tag: 'pedals');
    final done = task(priority: Priority.high).complete(now);
    final tasks = [high, medium, none, done];

    final all = matrixOf(tasks, now: now);
    expect(all[Quadrant.doFirst], [high]);
    expect(all[Quadrant.schedule], [medium]);
    expect(all[Quadrant.delegate], isEmpty);
    expect(all[Quadrant.drop], [none]);

    final dated = matrixOf(tasks, now: now, includeUndated: false);
    expect(dated[Quadrant.schedule], isEmpty);
    final tagged = matrixOf(tasks, now: now, tag: 'pedals');
    expect(tagged[Quadrant.doFirst], isEmpty);
    expect(tagged[Quadrant.drop], [none]);
  });

  group('warn_days in geas.yaml', () {
    test('parses, and defaults when missing', () {
      expect(RepoConfig.parse('format: 1\nwarn_days: 5\n').warnDays, 5);
      expect(RepoConfig.parse('format: 1\n').warnDays, isNull);
      expect(() => RepoConfig.parse('format: 1\nwarn_days: soon\n'),
          throwsFormatException);
      expect(() => RepoConfig.parse('format: 1\nwarn_days: -1\n'),
          throwsFormatException);
    });

    test('the workspace reads it', () async {
      final area = MemoryArea();
      expect((await Workspace.load(area)).warnDays, defaultWarnDays);
      await area.write(
          repoConfigPath, utf8.encode('format: 1\nwarn_days: 4\n'));
      expect((await Workspace.load(area)).warnDays, 4);
      await area.write(
          repoConfigPath, utf8.encode('format: 1\nwarn_days: x\n'));
      final broken = await Workspace.load(area);
      expect(broken.warnDays, defaultWarnDays);
      expect(broken.problems.keys, [repoConfigPath]);
    });
  });
}
