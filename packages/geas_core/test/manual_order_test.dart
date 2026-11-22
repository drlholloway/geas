import 'package:geas_core/geas_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 22, 12);
  var age = 0;
  Task task(String title, [int? position]) => Task.create(
        title: title,
        now: now.subtract(Duration(hours: ++age)),
      ).copyWith(position: position);
  List<String> titles(Iterable<Task> tasks) => [for (final t in tasks) t.title];

  /// [tasks] after [changed] replace the ones with their ids.
  List<Task> apply(List<Task> tasks, List<Task> changed) => manualOrder([
        for (final t in tasks)
          changed.where((c) => c.id == t.id).firstOrNull ?? t,
      ]);

  test('orders by position, then unplaced tasks by due date', () {
    final tasks = [
      task('third', 3000),
      task('unplaced, no date'),
      task('first', 1000),
      Task.create(
        title: 'unplaced, due',
        now: now,
        due: const Due.date(LocalDate(2026, 11, 23)),
      ),
      task('second', 2000),
    ];
    expect(titles(manualOrder(tasks)), [
      'first',
      'second',
      'third',
      'unplaced, due',
      'unplaced, no date',
    ]);
  });

  test('a task file keeps its position, and has no key without one', () {
    final plain = task('a');
    expect(plain.encode(), isNot(contains('position')));
    final placed = Task.parse(plain.copyWith(position: -512).encode());
    expect(placed.position, -512);
    expect(placed.encode(), contains('position: -512\n'));
    expect(
        Task.parse(placed.copyWith(position: null).encode()).position, isNull);
    expect(
        () => Task.parse(
            placed.encode().replaceFirst('position: -512', 'position: top')),
        throwsFormatException);
  });

  test('a list remembers that it is sorted by hand', () {
    const list = TaskList(id: 'pedals', name: 'Pedals');
    expect(list.manual, isFalse);
    expect(list.encode(), isNot(contains('sort')));
    final manual = TaskList.parse(list.copyWith(manual: true).encode());
    expect(manual.manual, isTrue);
    expect(manual.encode(), contains('sort: manual\n'));
    expect(TaskList.parse(manual.copyWith(manual: false).encode()).manual,
        isFalse);
    expect(TaskList.parse('id: a\nname: A\nsort: due\n').manual, isFalse);
  });

  group('moving a task', () {
    final a = task('a', 1024), b = task('b', 2048), c = task('c', 3072);
    final tasks = [a, b, c];

    test('between two others changes only its own position', () {
      final changed = moveInManualOrder(tasks, c.id, 1, now: now);
      expect(changed.single.id, c.id);
      expect(changed.single.position, 1536);
      expect(changed.single.updated, now);
      expect(titles(apply(tasks, changed)), ['a', 'c', 'b']);
    });

    test('to either end changes only its own position', () {
      final top = moveInManualOrder(tasks, c.id, 0, now: now);
      expect(top.single.position, 0);
      expect(titles(apply(tasks, top)), ['c', 'a', 'b']);
      final end = moveInManualOrder(tasks, a.id, 99, now: now);
      expect(end.single.position, 4096);
      expect(titles(apply(tasks, end)), ['b', 'c', 'a']);
    });

    test('where it already is, or of a task not there, changes nothing', () {
      expect(moveInManualOrder(tasks, b.id, 1, now: now), isEmpty);
      expect(moveInManualOrder(tasks, 'nope', 0, now: now), isEmpty);
    });

    test('with no room between neighbors renumbers them all', () {
      final tight = [task('a', 1), task('b', 2), task('c', 3)];
      final changed = moveInManualOrder(tight, tight[2].id, 1, now: now);
      expect(changed, hasLength(3));
      final after = apply(tight, changed);
      expect(titles(after), ['a', 'c', 'b']);
      expect([for (final t in after) t.position], [1024, 2048, 3072]);
    });

    test('with unplaced tasks about gives every task a position', () {
      final mixed = manualOrder([task('new'), a, b]);
      final changed = moveInManualOrder(mixed, b.id, 0, now: now);
      final after = apply(mixed, changed);
      expect(titles(after), ['b', 'a', 'new']);
      expect(after.every((t) => t.position != null), isTrue);
    });

    test('repeated moves between the same two run out of room and recover', () {
      var current = tasks;
      for (var i = 0; i < 15; i++) {
        final last = current.last;
        current =
            apply(current, moveInManualOrder(current, last.id, 1, now: now));
        expect(current[1].id, last.id);
      }
      expect({for (final t in current) t.position}, hasLength(3));
    });
  });

  test('a new task goes above the rest', () {
    expect(topPosition(const []), 0);
    expect(topPosition([task('a', 1024), task('b', -2048), task('c')]), -3072);
  });
}
