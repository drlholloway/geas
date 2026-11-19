import 'dart:convert';

import 'package:geas_core/geas_core.dart';
import 'package:geas_core/testing.dart';
import 'package:test/test.dart';

void main() {
  // A Wednesday.
  final now = DateTime(2026, 11, 18, 12);
  const today = LocalDate(2026, 11, 18);
  const lists = [
    TaskList(id: 'pedals', name: 'Pedals'),
    TaskList(id: 'home', name: 'Home Repairs'),
  ];
  var age = 0;
  Task task(
    String title, {
    String list = inboxId,
    List<String> tags = const [],
    int? due,
    Priority priority = Priority.none,
    String body = '',
    bool done = false,
  }) {
    final t = Task.create(
      title: title,
      now: now.subtract(Duration(hours: ++age)),
      list: list,
      tags: tags,
      due: due == null ? null : Due.date(today.addDays(due)),
      priority: priority,
      body: body,
    );
    return done ? t.complete(now.subtract(Duration(minutes: age))) : t;
  }

  final tasks = [
    task('Order 1N914s',
        list: 'pedals', tags: ['Tayda'], due: 0, priority: Priority.high),
    task('Order knobs', list: 'pedals', tags: ['tayda'], due: 9),
    task('Fix the door', list: 'home', due: -2, body: 'Order a hinge first.'),
    task('Call the dentist', tags: ['errands'], priority: Priority.low),
    task('Solder the fuzz', list: 'pedals', done: true),
    task('Old order', done: true, tags: ['tayda']),
  ];
  List<String> find(String text) => TaskQuery.parse(text, lists: lists)
      .search(tasks, now)
      .map((t) => t.title)
      .toList();

  test('words match the title or notes, all of them, any case', () {
    expect(find('order'), ['Fix the door', 'Order 1N914s', 'Order knobs']);
    expect(find('ORDER hinge'), ['Fix the door']);
    expect(find('order zebra'), isEmpty);
  });

  test('tags, lists and priority', () {
    expect(find('#tayda'), ['Order 1N914s', 'Order knobs']);
    expect(find('#tayda #errands'),
        ['Order 1N914s', 'Order knobs', 'Call the dentist']);
    expect(find('^pedals'), ['Order 1N914s', 'Order knobs']);
    expect(find('^home-repairs ^inbox'), ['Fix the door', 'Call the dentist']);
    expect(find('!high'), ['Order 1N914s']);
    expect(find('!none ^pedals'), ['Order knobs']);
    expect(find('^nosuchlist'), isEmpty);
  });

  test('due windows', () {
    expect(find('due:overdue'), ['Fix the door']);
    expect(find('due:today'), ['Fix the door', 'Order 1N914s']);
    expect(find('due:week'), ['Fix the door', 'Order 1N914s']);
    expect(find('due:any'), ['Fix the door', 'Order 1N914s', 'Order knobs']);
    expect(find('due:none'), ['Call the dentist']);
    expect(find('due:someday'), isEmpty);
  });

  test('finished tasks only when asked for, after the open ones', () {
    expect(find('is:done'), ['Solder the fuzz', 'Old order']);
    expect(find('#tayda is:all'), ['Order 1N914s', 'Order knobs', 'Old order']);
    expect(find('is:done is:open !low'), ['Call the dentist']);
  });

  test('an empty query says so and matches every open task', () {
    expect(TaskQuery.parse('  ').isEmpty, isTrue);
    expect(TaskQuery.parse('x').isEmpty, isFalse);
    expect(TaskQuery.parse('^nope').isEmpty, isFalse);
    expect(find(''), hasLength(4));
  });

  group('saved filters', () {
    test('a new filter gets an id from its name and goes last', () {
      final first = newFilter('Tayda orders', '#tayda order', const []);
      expect(first.id, 'tayda-orders');
      expect(first.encode(),
          'id: tayda-orders\nname: Tayda orders\nquery: "#tayda order"\norder: 1\n');
      final second = newFilter('Overdue', ' due:overdue ', [first]);
      expect(second.order, 2);
      expect(second.query, 'due:overdue');
      expect(
          () => newFilter('tayda ORDERS', 'x', [first]), throwsFormatException);
      expect(() => newFilter('?', 'x', const []), throwsFormatException);
    });

    test('a rewrite keeps comments and unknown keys', () {
      const text = '# mine\nid: late\nname: Late\nquery: due:overdue\n'
          'color: red\n';
      final filter = SavedFilter.parse(text);
      expect(filter.encode(), text);
      expect(filter.copyWith(name: 'Overdue').encode(),
          '# mine\nid: late\nname: Overdue\nquery: due:overdue\ncolor: red\n');
      expect(() => SavedFilter.parse('name: x\n'), throwsFormatException);
    });

    test('the workspace keeps them, and sync merges them key by key', () async {
      final area = MemoryStore().working;
      final workspace = await Workspace.load(area);
      final late = await workspace
          .saveFilter(newFilter('Late', 'due:overdue', const []));
      await workspace.saveFilter(newFilter('Tayda', '#tayda', [late]));
      expect((await Workspace.load(area)).filters.map((f) => f.name),
          ['Late', 'Tayda']);
      await workspace.deleteFilter('late');
      expect((await area.readAll()).keys, ['filters/tayda.yaml']);

      Map<String, List<int>> file(SavedFilter f) =>
          {filterPath(f.id): utf8.encode(f.encode())};
      final merged = mergeTrees(
        base: file(late),
        local: file(late.copyWith(name: 'Overdue')),
        remote: file(late.copyWith(query: 'due:overdue !high')),
        now: now,
      );
      final result =
          SavedFilter.parse(utf8.decode(merged.files['filters/late.yaml']!));
      expect(result.name, 'Overdue');
      expect(result.query, 'due:overdue !high');
      expect(merged.conflicts, isEmpty);
    });
  });
}
