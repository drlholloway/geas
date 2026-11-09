import 'dart:math';

import 'package:geas_core/geas_core.dart';
import 'package:test/test.dart';

/// The example from TODO.md, comments and all.
const _example = '''---
id: 01JC8ZQ4R7ME2X5Y9V3T6N0B4K
title: Order 1N914s
list: inbox                    # list id; inbox is built in
tags: [tayda, pedals]
due: 2026-11-12                # or 2026-11-12T09:00-06:00 with a time
priority: high                 # none | low | medium | high
created: 2026-11-08T23:41:02Z
updated: 2026-11-08T23:41:02Z
completed: null                # UTC timestamp once done
---
Notes go here as Markdown.

- [ ] check Tayda stock
- [x] pick pots
''';

void main() {
  final now = DateTime.utc(2026, 11, 9, 8, 15, 30);

  group('parse', () {
    test('reads every field', () {
      final task = Task.parse(_example);
      expect(task.id, '01JC8ZQ4R7ME2X5Y9V3T6N0B4K');
      expect(task.title, 'Order 1N914s');
      expect(task.list, 'inbox');
      expect(task.tags, ['tayda', 'pedals']);
      expect(task.due, const Due.date(LocalDate(2026, 11, 12)));
      expect(task.priority, Priority.high);
      expect(task.created, DateTime.utc(2026, 11, 8, 23, 41, 2));
      expect(task.updated, task.created);
      expect(task.completed, isNull);
      expect(task.body, startsWith('Notes go here'));
      expect(task.checklist.map((i) => i.text),
          ['check Tayda stock', 'pick pots']);
    });

    test('fills in defaults for a minimal hand-written file', () {
      final task = Task.parse('''---
id: hand-made
title: Water the plants
created: 2026-11-08T12:00:00Z
updated: 2026-11-08T12:00:00Z
---
''');
      expect(task.list, inboxId);
      expect(task.tags, isEmpty);
      expect(task.due, isNull);
      expect(task.priority, Priority.none);
      expect(task.body, '');
    });

    test('accepts block-style tags, a single tag and numeric titles', () {
      final task = Task.parse('''---
id: a
title: 1999
tags:
  - one
  - 2
created: 2026-11-08T12:00:00Z
updated: 2026-11-08T12:00:00-06:00
---
''');
      expect(task.title, '1999');
      expect(task.tags, ['one', '2']);
      expect(task.updated, DateTime.utc(2026, 11, 8, 18));

      final single = Task.parse(
          '---\nid: b\ntitle: t\ntags: solo\ncreated: 2026-11-08T12:00:00Z\n'
          'updated: 2026-11-08T12:00:00Z\n---\n');
      expect(single.tags, ['solo']);
    });

    test('accepts CRLF line endings', () {
      final task = Task.parse(_example.replaceAll('\n', '\r\n'));
      expect(task.title, 'Order 1N914s');
      expect(task.body, startsWith('Notes go here'));
    });

    for (final (name, text) in [
      ('no frontmatter', 'Just notes\n'),
      ('unclosed frontmatter', '---\nid: a\ntitle: t\n'),
      (
        'no id',
        '---\ntitle: t\ncreated: 2026-11-08T12:00:00Z\nupdated: 2026-11-08T12:00:00Z\n---\n'
      ),
      (
        'a bad id',
        '---\nid: a/b\ntitle: t\ncreated: 2026-11-08T12:00:00Z\nupdated: 2026-11-08T12:00:00Z\n---\n'
      ),
      (
        'no title',
        '---\nid: a\ncreated: 2026-11-08T12:00:00Z\nupdated: 2026-11-08T12:00:00Z\n---\n'
      ),
      (
        'a bad due',
        '---\nid: a\ntitle: t\ndue: someday\ncreated: 2026-11-08T12:00:00Z\nupdated: 2026-11-08T12:00:00Z\n---\n'
      ),
      (
        'a bad priority',
        '---\nid: a\ntitle: t\npriority: 11\ncreated: 2026-11-08T12:00:00Z\nupdated: 2026-11-08T12:00:00Z\n---\n'
      ),
      (
        'a bad timestamp',
        '---\nid: a\ntitle: t\ncreated: yesterday\nupdated: 2026-11-08T12:00:00Z\n---\n'
      ),
      ('a list as frontmatter', '---\n- a\n- b\n---\n'),
      ('invalid YAML', '---\nid: [a\n---\n'),
    ]) {
      test('rejects $name', () {
        expect(() => Task.parse(text), throwsFormatException);
      });
    }
  });

  group('encode', () {
    test('an unchanged task writes back byte for byte', () {
      expect(Task.parse(_example).encode(), _example);
    });

    test('an edit touches only the changed lines', () {
      final task = Task.parse(_example)
          .copyWith(list: 'pedals', updated: now)
          .complete(now);
      final lines = task.encode().split('\n');
      final original = _example.split('\n');
      final changed = [
        for (var i = 0; i < lines.length; i++)
          if (lines[i] != original[i]) lines[i],
      ];
      expect(changed, [
        'list: pedals                    # list id; inbox is built in',
        'updated: 2026-11-09T08:15:30Z',
        'completed: 2026-11-09T08:15:30Z                # UTC timestamp once done',
      ]);
    });

    test('unknown keys and comments survive an edit', () {
      const text = '''---
# My own note about this task
id: a
title: Old
mood: grumpy
estimate: {hours: 2}
created: 2026-11-08T12:00:00Z
updated: 2026-11-08T12:00:00Z
---
body
''';
      final out =
          Task.parse(text).copyWith(title: 'New', updated: now).encode();
      expect(out, contains('# My own note about this task\n'));
      expect(out, contains('mood: grumpy\n'));
      expect(out, contains('estimate: {hours: 2}\n'));
      expect(out, contains('title: New\n'));
      expect(Task.parse(out).title, 'New');
      expect(out, endsWith('---\nbody\n'));
    });

    test('fields missing from a hand-written file are added only when set', () {
      const text = '---\nid: a\ntitle: t\ncreated: 2026-11-08T12:00:00Z\n'
          'updated: 2026-11-08T12:00:00Z\n---\n';
      expect(Task.parse(text).encode(), text);

      final edited = Task.parse(text)
          .copyWith(priority: Priority.low, tags: ['x'], updated: now)
          .encode();
      expect(edited, contains('priority: low\n'));
      expect(edited, contains('tags: [x]\n'));
      expect(edited, isNot(contains('due:')));
    });

    test('clearing a field writes its empty value', () {
      final task =
          Task.parse(_example).copyWith(due: null, tags: [], updated: now);
      final out = task.encode();
      expect(out, contains('due: null'));
      expect(out, contains('tags: []'));
      expect(Task.parse(out).due, isNull);
    });

    test('a new task uses the canonical layout', () {
      final task = Task.create(
        title: 'Order 1N914s',
        now: DateTime.utc(2026, 11, 8, 23, 41, 2, 999),
        tags: ['tayda', 'pedals'],
        due: Due.parse('2026-11-12T09:00-06:00'),
        priority: Priority.high,
        body: 'Notes\n',
        random: Random(1),
      );
      expect(task.encode(), '''---
id: ${task.id}
title: Order 1N914s
list: inbox
tags: [tayda, pedals]
due: 2026-11-12T09:00-06:00
priority: high
created: 2026-11-08T23:41:02Z
updated: 2026-11-08T23:41:02Z
completed: null
---
Notes
''');
      expect(isUlid(task.id), isTrue);
    });

    for (final title in [
      'yes: no # not a comment',
      '- looks like a list',
      '"quoted"',
      '  padded  ',
      '#hashtag',
      'null',
      '42',
      '',
      'line one\nline two',
      'Ünïcödé ✓',
      "it's",
      '[bracketed]',
    ]) {
      test('round-trips the title ${title.replaceAll('\n', r'\n')}', () {
        final task = Task.create(title: title, now: now);
        expect(Task.parse(task.encode()).title, title);
        final edited = Task.parse(_example).copyWith(title: title);
        expect(Task.parse(edited.encode()).title, title);
      });
    }

    for (final tag in ['a,b', 'x: y', '#t', '[t]', 'two words', 'true']) {
      test('round-trips the tag $tag', () {
        final task = Task.create(title: 't', now: now, tags: [tag, 'plain']);
        expect(Task.parse(task.encode()).tags, [tag, 'plain']);
      });
    }

    test('parse, encode and parse again gives an equal task', () {
      final task = Task.parse(_example);
      expect(Task.parse(task.encode()), task);
    });
  });

  group('edits', () {
    test('complete and reopen set completed and updated', () {
      final task = Task.parse(_example).complete(now);
      expect(task.completed, DateTime.utc(2026, 11, 9, 8, 15, 30));
      expect(task.updated, task.completed);
      final reopened = task.reopen(now.add(const Duration(minutes: 1)));
      expect(reopened.completed, isNull);
      expect(reopened.isCompleted, isFalse);
    });

    test('timestamps are kept in UTC to the second', () {
      final task = Task.create(
          title: 't', now: DateTime.utc(2026, 1, 1, 0, 0, 0, 750).toLocal());
      expect(task.created, DateTime.utc(2026, 1, 1));
      expect(task.created.isUtc, isTrue);
    });

    test('checking an item edits the body and bumps updated', () {
      final task = Task.parse(_example);
      final item = task.checklist.first;
      final done = task.setChecklistItem(item.line, done: true, now: now);
      expect(done.checklist.map((i) => i.done), [true, true]);
      expect(done.updated, now);
      expect(done.encode(), contains('- [x] check Tayda stock\n'));
    });
  });
}
