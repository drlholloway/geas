import 'package:geas_core/geas_core.dart';
import 'package:test/test.dart';

// Local times throughout, so the tests hold in any time zone.
final _now = DateTime(2026, 11, 8, 12);
var _seq = 0;

Task _task(
  String title, {
  String? due,
  Priority priority = Priority.none,
  String list = inboxId,
  List<String> tags = const [],
  DateTime? completed,
  DateTime? created,
}) {
  final at = created ?? DateTime.utc(2026, 11, 1, 0, 0, _seq++);
  return Task(
    id: title,
    title: title,
    list: list,
    tags: tags,
    due: due == null ? null : Due.parse(due),
    priority: priority,
    created: at,
    updated: at,
    completed: completed,
  );
}

List<String> _titles(List<Task> tasks) => [for (final t in tasks) t.title];

void main() {
  group('dueBucket', () {
    test('date-only tasks', () {
      expect(dueBucket(_task('a', due: '2026-11-07'), _now), DueBucket.overdue);
      expect(dueBucket(_task('a', due: '2026-11-08'), _now), DueBucket.today);
      expect(
          dueBucket(_task('a', due: '2026-11-09'), _now), DueBucket.upcoming);
      expect(dueBucket(_task('a'), _now), DueBucket.noDate);
    });

    test('a timed task is overdue once its time passes', () {
      expect(dueBucket(_task('a', due: '2026-11-08T11:59'), _now),
          DueBucket.overdue);
      expect(dueBucket(_task('a', due: '2026-11-08T12:01'), _now),
          DueBucket.today);
    });

    test('a timed task with an offset compares by instant', () {
      final now = DateTime.utc(2026, 11, 8, 15, 30);
      expect(dueBucket(_task('a', due: '2026-11-08T09:00-06:00'), now),
          DueBucket.overdue);
      expect(dueBucket(_task('a', due: '2026-11-08T10:00-06:00'), now),
          isNot(DueBucket.overdue));
    });
  });

  group('openTasks', () {
    final tasks = [
      _task('overdue', due: '2026-11-01'),
      _task('today', due: '2026-11-08'),
      _task('in six days', due: '2026-11-14', list: 'work'),
      _task('in seven days', due: '2026-11-15'),
      _task('no date', tags: ['Pedals']),
      _task('done', due: '2026-11-08', completed: DateTime.utc(2026, 11, 8)),
    ];

    test('leaves out completed tasks and sorts by due', () {
      expect(_titles(openTasks(tasks, now: _now)),
          ['overdue', 'today', 'in six days', 'in seven days', 'no date']);
    });

    test('windows', () {
      expect(_titles(openTasks(tasks, now: _now, window: DueWindow.overdue)),
          ['overdue']);
      expect(_titles(openTasks(tasks, now: _now, window: DueWindow.today)),
          ['today']);
      expect(_titles(openTasks(tasks, now: _now, window: DueWindow.next7Days)),
          ['today', 'in six days']);
    });

    test('by list and by tag, ignoring tag case', () {
      expect(
          _titles(openTasks(tasks, now: _now, list: 'work')), ['in six days']);
      expect(_titles(openTasks(tasks, now: _now, tag: 'pedals')), ['no date']);
    });
  });

  group('compareByDue', () {
    test('same day: all-day first, then by time', () {
      final tasks = [
        _task('evening', due: '2026-11-10T18:00'),
        _task('morning', due: '2026-11-10T08:00'),
        _task('all day', due: '2026-11-10'),
      ]..sort(compareByDue);
      expect(_titles(tasks), ['all day', 'morning', 'evening']);
    });

    test('same due: highest priority, then oldest', () {
      final tasks = [
        _task('low', due: '2026-11-10', priority: Priority.low),
        _task('newer high',
            due: '2026-11-10',
            priority: Priority.high,
            created: DateTime.utc(2026, 11, 5)),
        _task('older high',
            due: '2026-11-10',
            priority: Priority.high,
            created: DateTime.utc(2026, 11, 4)),
      ]..sort(compareByDue);
      expect(_titles(tasks), ['older high', 'newer high', 'low']);
    });
  });

  test('completedTasks lists the most recently done first', () {
    final tasks = [
      _task('open'),
      _task('earlier', completed: DateTime.utc(2026, 11, 1)),
      _task('later', completed: DateTime.utc(2026, 11, 7)),
    ];
    expect(_titles(completedTasks(tasks)), ['later', 'earlier']);
  });

  test('allTags merges spellings that differ only in case', () {
    final tasks = [
      _task('a', tags: ['pedals', 'Tayda']),
      _task('b', tags: ['Pedals', 'audio']),
    ];
    expect(allTags(tasks), ['audio', 'pedals', 'Tayda']);
  });

  test('replaceTag renames or removes a tag in any case', () {
    expect(replaceTag(['Pedals', 'tayda'], 'pedals', 'builds'),
        ['builds', 'tayda']);
    expect(replaceTag(['pedals', 'tayda'], 'TAYDA', null), ['pedals']);
    expect(replaceTag(['a', 'b'], 'a', 'B'), ['B']);
  });
}
