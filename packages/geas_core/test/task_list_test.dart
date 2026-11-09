import 'package:geas_core/geas_core.dart';
import 'package:test/test.dart';

void main() {
  test('parses a list file', () {
    final list = TaskList.parse('id: pedals\nname: Pedals\ncolor: "#4a90d9"\n'
        'order: 2\n');
    expect(
        list,
        const TaskList(
            id: 'pedals', name: 'Pedals', color: '#4a90d9', order: 2));
  });

  test('defaults color and order', () {
    final list = TaskList.parse('id: home\nname: Home\n');
    expect(list.color, isNull);
    expect(list.order, 0);
  });

  test('a new list is written in canonical order, quoting the color', () {
    const list = TaskList(id: 'pedals', name: 'Pedals', color: '#4a90d9');
    expect(list.encode(),
        'id: pedals\nname: Pedals\ncolor: "#4a90d9"\norder: 0\n');
    expect(TaskList.parse(list.encode()), list);
  });

  test('an edit keeps comments and unknown keys', () {
    const text = '# Guitar stuff\nid: pedals\nname: Pedals\nicon: guitar\n';
    final renamed = TaskList.parse(text).copyWith(name: 'Effects').encode();
    expect(
        renamed, '# Guitar stuff\nid: pedals\nname: Effects\nicon: guitar\n');
    expect(TaskList.parse(text).encode(), text);
  });

  for (final (name, text) in [
    ('no name', 'id: a\n'),
    ('a bad id', 'id: a b\nname: A\n'),
    ('a fractional order', 'id: a\nname: A\norder: 1.5\n'),
    ('not a map', '- a\n'),
  ]) {
    test('rejects $name', () {
      expect(() => TaskList.parse(text), throwsFormatException);
    });
  }

  group('withInbox', () {
    test('puts the built-in inbox first', () {
      final lists = withInbox(const [
        TaskList(id: 'b', name: 'B', order: 1),
        TaskList(id: 'z', name: 'Z'),
        TaskList(id: 'a', name: 'A'),
      ]);
      expect(lists.map((l) => l.id), [inboxId, 'a', 'z', 'b']);
    });

    test('uses an inbox file in place of the built-in one', () {
      final lists = withInbox(const [
        TaskList(id: 'a', name: 'A'),
        TaskList(id: inboxId, name: 'In tray', order: 5),
      ]);
      expect(lists.map((l) => l.name), ['A', 'In tray']);
    });
  });
}
