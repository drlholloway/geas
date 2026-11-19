import 'dart:math';

import 'package:geas_core/geas_core.dart';
import 'package:test/test.dart';

void main() {
  // A Wednesday.
  final now = DateTime(2026, 11, 18, 12);
  const today = LocalDate(2026, 11, 18);

  test('parses the file form and what people type', () {
    expect(Repeat.parse('daily'), const Repeat(1, RepeatUnit.day));
    expect(Repeat.parse('Weekdays'), const Repeat.weekdays());
    expect(Repeat.parse('2w'), const Repeat(2, RepeatUnit.week));
    expect(Repeat.parse('every 6 weeks'), const Repeat(6, RepeatUnit.week));
    expect(Repeat.parse('every month'), const Repeat(1, RepeatUnit.month));
    expect(Repeat.parse('10 days'), const Repeat(10, RepeatUnit.day));
    for (final bad in ['', 'often', '0d', '2x', 'every']) {
      expect(() => Repeat.parse(bad), throwsFormatException, reason: bad);
    }
  });

  test('writes the short form and a label', () {
    for (final text in ['daily', 'weekdays', 'weekly', 'monthly', 'yearly']) {
      expect('${Repeat.parse(text)}', text);
    }
    expect('${Repeat.parse('every 2 weeks')}', '2w');
    expect(Repeat.parse('1d').toString(), 'daily');
    expect(Repeat.parse('3m').label, 'Every 3 months');
    expect(Repeat.parse('weekly').label, 'Every week');
    expect(const Repeat.weekdays().label, 'Every weekday');
  });

  test('steps to the next date', () {
    expect(Repeat.parse('10d').after(today), const LocalDate(2026, 11, 28));
    expect(Repeat.parse('2w').after(today), const LocalDate(2026, 12, 2));
    expect(const Repeat.weekdays().after(const LocalDate(2026, 11, 20)),
        const LocalDate(2026, 11, 23)); // Friday to Monday
    expect(Repeat.parse('monthly').after(const LocalDate(2027, 1, 31)),
        const LocalDate(2027, 2, 28));
    expect(Repeat.parse('monthly').after(const LocalDate(2026, 12, 15)),
        const LocalDate(2027, 1, 15));
    expect(Repeat.parse('yearly').after(const LocalDate(2028, 2, 29)),
        const LocalDate(2029, 2, 28));
  });

  group('the task file', () {
    test('a task that doesn\'t repeat has no repeat key', () {
      final task = Task.create(title: 'Water the plants', now: now);
      expect(task.encode(), isNot(contains('repeat')));
      expect(Task.parse(task.encode()).repeat, isNull);
    });

    test('repeat round-trips and can be cleared', () {
      final task = Task.create(title: 'Water the plants', now: now)
          .copyWith(repeat: Repeat.parse('every 2 weeks'));
      expect(task.encode(), contains('repeat: 2w\n'));
      final read = Task.parse(task.encode());
      expect(read, task);
      expect(read.encode(), task.encode());
      final cleared = Task.parse(read.copyWith(repeat: null).encode());
      expect(cleared.repeat, isNull);
    });

    test('a bad repeat is refused', () {
      final text = Task.create(title: 'x', now: now)
          .copyWith(repeat: Repeat.parse('daily'))
          .encode()
          .replaceFirst('repeat: daily', 'repeat: sometimes');
      expect(() => Task.parse(text), throwsFormatException);
    });
  });

  group('completeTask', () {
    Task task({Due? due, String repeat = 'weekly', String body = ''}) =>
        Task.create(
          title: 'Water the plants',
          now: now.subtract(const Duration(days: 30)),
          list: 'home',
          tags: ['garden'],
          due: due,
          priority: Priority.medium,
          body: body,
        ).copyWith(repeat: Repeat.parse(repeat));

    test('a task that doesn\'t repeat is just finished', () {
      final plain = Task.create(title: 'Once', now: now);
      final result = completeTask(plain, now);
      expect(result.single.isCompleted, isTrue);
      expect(result.single.id, plain.id);
    });

    test('finishes it and adds the next one', () {
      final original = task(
        due: const Due.date(today),
        body: 'Notes.\n\n- [x] fern\n- [ ] ficus\n',
      );
      final [done, next] = completeTask(original, now, random: Random(1));
      expect(done.id, original.id);
      expect(done.isCompleted, isTrue);
      expect(done.repeat, isNull);

      expect(next.id, isNot(original.id));
      expect(next.isCompleted, isFalse);
      expect(next.title, 'Water the plants');
      expect(next.list, 'home');
      expect(next.tags, ['garden']);
      expect(next.priority, Priority.medium);
      expect(next.repeat, Repeat.parse('weekly'));
      expect(next.due, const Due.date(LocalDate(2026, 11, 25)));
      expect(next.body, 'Notes.\n\n- [ ] fern\n- [ ] ficus\n');
      expect(next.order, isNull);
    });

    test('skips occurrences already missed', () {
      final late = task(due: const Due.date(LocalDate(2026, 10, 28)));
      expect(completeTask(late, now).last.due,
          const Due.date(LocalDate(2026, 11, 25)));
    });

    test('done early, the next still counts from the due date', () {
      final early = task(due: const Due.date(LocalDate(2026, 11, 20)));
      expect(completeTask(early, now).last.due,
          const Due.date(LocalDate(2026, 11, 27)));
    });

    test('with no due date, counts from today', () {
      expect(completeTask(task(repeat: '3d'), now).last.due,
          const Due.date(LocalDate(2026, 11, 21)));
    });

    test('keeps the time of day', () {
      final at = now.timeZoneOffset;
      final timed = task(due: Due.at(today, 9, 30, offset: at));
      final next = completeTask(timed, now).last.due!;
      expect(next.date, const LocalDate(2026, 11, 25));
      expect((next.hour, next.minute), (9, 30));
      expect(next.instant!.toLocal(), DateTime(2026, 11, 25, 9, 30));
    });

    test('finishing the finished one again adds nothing', () {
      final [done, _] = completeTask(task(due: const Due.date(today)), now);
      expect(completeTask(done.reopen(now), now), hasLength(1));
    });
  });

  group('reopenTask', () {
    Task weekly() => Task.create(
          title: 'Water the plants',
          now: now.subtract(const Duration(days: 30)),
          due: const Due.date(today),
        ).copyWith(repeat: Repeat.parse('weekly'));
    final later = now.add(const Duration(minutes: 5));

    test('takes back the next one and the repeat', () {
      final [done, next] = completeTask(weekly(), now);
      final result = reopenTask(done, [done, next], later);
      expect(result.replaced, next);
      expect(result.task.id, done.id);
      expect(result.task.isCompleted, isFalse);
      expect(result.task.repeat, Repeat.parse('weekly'));
      expect(result.task.due, const Due.date(today));
      // Finishing it again makes one next task, not two.
      expect(completeTask(result.task, later), hasLength(2));
    });

    test('leaves a next one that was finished, renamed or is gone', () {
      final [done, next] = completeTask(weekly(), now);
      for (final others in [
        [done, next.complete(later)],
        [done, next.copyWith(title: 'Water the ferns')],
        [done],
      ]) {
        final result = reopenTask(done, others, later);
        expect(result.replaced, isNull);
        expect(result.task.isCompleted, isFalse);
        expect(result.task.repeat, isNull);
      }
    });

    test('a task that never repeated just reopens', () {
      final plain = Task.create(title: 'Once', now: now).complete(now);
      final other = Task.create(title: 'Once', now: now)
          .copyWith(repeat: Repeat.parse('daily'));
      // Another repeating task of the same name, made at the same moment
      // by hand, is the one case this can't tell apart.
      expect(reopenTask(plain, [plain], later).replaced, isNull);
      expect(reopenTask(plain, [plain, other], later).replaced, other);
    });
  });
}
