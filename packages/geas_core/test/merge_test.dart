import 'dart:convert';

import 'package:geas_core/geas_core.dart';
import 'package:test/test.dart';

const _id = '01JC8ZQ4R7ME2X5Y9V3T6N0B4K';
const _path = 'tasks/$_id.md';
final _now = DateTime.utc(2026, 11, 9, 12);

String _task({
  String title = 'Order 1N914s',
  String list = 'inbox',
  String priority = 'none',
  String updated = '2026-11-09T08:00:00Z',
  String completed = 'null',
  String extra = '',
  String body = 'Notes.\n\n- [ ] check stock\n- [ ] pick pots\n',
}) =>
    '''---
id: $_id
title: $title
list: $list
tags: [pedals]
priority: $priority
created: 2026-11-08T23:41:02Z
updated: $updated
completed: $completed
$extra---
$body''';

Map<String, List<int>> _files(Map<String, String> texts) =>
    texts.map((path, text) => MapEntry(path, utf8.encode(text)));

TreeMerge _merge({
  Map<String, String> base = const {},
  Map<String, String> local = const {},
  Map<String, String> remote = const {},
}) =>
    mergeTrees(
      base: _files(base),
      local: _files(local),
      remote: _files(remote),
      now: _now,
    );

Map<String, String> _texts(TreeMerge merge) =>
    merge.files.map((path, bytes) => MapEntry(path, utf8.decode(bytes)));

Task _only(TreeMerge merge) =>
    Task.parse(utf8.decode(merge.files.values.single));

void main() {
  final base = {_path: _task()};

  group('one side changed', () {
    test('takes the local edit', () {
      final local = {_path: _task(title: 'Order 1N4148s')};
      final merge = _merge(base: base, local: local, remote: base);
      expect(_texts(merge), local);
      expect(merge.conflicts, isEmpty);
    });

    test('takes the remote edit', () {
      final remote = {_path: _task(priority: 'high')};
      expect(_texts(_merge(base: base, local: base, remote: remote)), remote);
    });

    test('takes a deletion', () {
      expect(_merge(base: base, local: base, remote: {}).files, isEmpty);
      expect(_merge(base: base, local: {}, remote: base).files, isEmpty);
    });

    test('takes new tasks from both sides', () {
      const other = 'tasks/01JC8ZQ4R7ME2X5Y9V3T6NWXYZ.md';
      final otherText = _task().replaceFirst(_id, '01JC8ZQ4R7ME2X5Y9V3T6NWXYZ');
      final merge = _merge(local: {_path: _task()}, remote: {other: otherText});
      expect(merge.files.keys, unorderedEquals([_path, other]));
    });

    test('leaves other files alone', () {
      final files = {'geas.yaml': 'format: 1\n', 'README.md': '# Tasks\n'};
      expect(_texts(_merge(base: files, local: files, remote: files)), files);
    });
  });

  group('both sides changed', () {
    test('different fields combine', () {
      final merge = _merge(
        base: base,
        local: {
          _path: _task(title: 'Order 1N4148s', updated: '2026-11-09T09:00:00Z')
        },
        remote: {
          _path: _task(priority: 'high', updated: '2026-11-09T10:00:00Z')
        },
      );
      final task = _only(merge);
      expect(task.title, 'Order 1N4148s');
      expect(task.priority, Priority.high);
      expect(task.updated, DateTime.utc(2026, 11, 9, 10));
      expect(merge.conflicts, isEmpty);
    });

    test('updated becomes the later of the two', () {
      final merge = _merge(
        base: base,
        local: {_path: _task(title: 'A', updated: '2026-11-09T11:00:00Z')},
        remote: {_path: _task(list: 'pedals', updated: '2026-11-09T10:00:00Z')},
      );
      expect(_only(merge).updated, DateTime.utc(2026, 11, 9, 11));
    });

    test('the same field: the newer edit wins and the other is set aside', () {
      final local =
          _task(title: 'Local title', updated: '2026-11-09T11:00:00Z');
      final merge = _merge(
        base: base,
        local: {_path: local},
        remote: {
          _path: _task(title: 'Remote title', updated: '2026-11-09T10:00:00Z')
        },
      );
      expect(_only(merge).title, 'Local title');
      final conflict = merge.conflicts.single;
      expect(conflict.kind, ConflictKind.fields);
      expect(conflict.key, _id);
      expect(conflict.fields, ['title']);
      expect(conflict.keptLocal, isTrue);
      expect(conflict.setAside, contains('title: Remote title'));
    });

    test('a tie on updated goes to the remote', () {
      final merge = _merge(
        base: base,
        local: {_path: _task(title: 'Local')},
        remote: {_path: _task(title: 'Remote')},
      );
      expect(_only(merge).title, 'Remote');
      expect(merge.conflicts.single.keptLocal, isFalse);
    });

    test('checklist edits on different lines combine', () {
      final merge = _merge(
        base: base,
        local: {
          _path: _task(
              title: 'T',
              body: 'Notes.\n\n- [x] check stock\n- [ ] pick pots\n')
        },
        remote: {
          _path: _task(
              priority: 'low',
              body: 'Notes.\n\n- [ ] check stock\n- [x] pick pots\n')
        },
      );
      expect(_only(merge).checklist.map((i) => i.done), [true, true]);
      expect(merge.conflicts, isEmpty);
    });

    test('overlapping body edits: the newer body wins', () {
      final merge = _merge(
        base: base,
        local: {
          _path: _task(body: 'Local notes.\n', updated: '2026-11-09T09:00:00Z')
        },
        remote: {
          _path: _task(body: 'Remote notes.\n', updated: '2026-11-09T10:00:00Z')
        },
      );
      expect(_only(merge).body, 'Remote notes.\n');
      expect(merge.conflicts.single.fields, ['body']);
    });

    test('unknown keys merge too', () {
      final merge = _merge(
        base: {_path: _task(extra: 'mood: calm\n')},
        local: {
          _path: _task(
              extra: 'mood: calm\nestimate: 2h\n',
              updated: '2026-11-09T09:00:00Z')
        },
        remote: {
          _path: _task(extra: 'mood: grumpy\n', updated: '2026-11-09T10:00:00Z')
        },
      );
      final text = utf8.decode(merge.files.values.single);
      expect(text, contains('mood: grumpy'));
      expect(text, contains('estimate: 2h'));
      expect(merge.conflicts, isEmpty);
    });

    test('a key removed on one side and untouched on the other is removed', () {
      final merge = _merge(
        base: {_path: _task(extra: 'mood: calm\n')},
        local: {_path: _task(title: 'T', updated: '2026-11-09T09:00:00Z')},
        remote: {
          _path: _task(
              extra: 'mood: calm\n',
              priority: 'low',
              updated: '2026-11-09T10:00:00Z')
        },
      );
      expect(utf8.decode(merge.files.values.single), isNot(contains('mood')));
    });

    test('keeps the remote file layout and comments', () {
      final remote = _task(priority: 'high', updated: '2026-11-09T10:00:00Z')
          .replaceFirst('list: inbox', 'list: inbox   # built in');
      final merge = _merge(
        base: base,
        local: {_path: _task(title: 'T', updated: '2026-11-09T09:00:00Z')},
        remote: {_path: remote},
      );
      expect(utf8.decode(merge.files.values.single),
          contains('list: inbox   # built in'));
    });
  });

  group('edited and deleted', () {
    test('keeps the local edit when the remote deleted it', () {
      final local = {_path: _task(title: 'Edited')};
      final merge = _merge(base: base, local: local, remote: {});
      expect(_texts(merge), local);
      final conflict = merge.conflicts.single;
      expect(conflict.kind, ConflictKind.editedAndDeleted);
      expect(conflict.keptLocal, isTrue);
    });

    test('keeps the remote edit when this device deleted it', () {
      final remote = {_path: _task(title: 'Edited')};
      final merge = _merge(base: base, local: {}, remote: remote);
      expect(_texts(merge), remote);
      expect(merge.conflicts.single.keptLocal, isFalse);
    });

    test('deleted on both sides is simply gone', () {
      final merge = _merge(base: base, local: {}, remote: {});
      expect(merge.files, isEmpty);
      expect(merge.conflicts, isEmpty);
    });
  });

  group('archiving', () {
    test('a task done over 30 days ago moves to archive/', () {
      final done = {_path: _task(completed: '2026-09-01T00:00:00Z')};
      final merge = _merge(base: done, local: done, remote: done);
      expect(merge.files.keys, ['archive/2026/$_id.md']);
    });

    test('an edit merges into a task the other side archived', () {
      const archived = 'archive/2026/$_id.md';
      final merge = _merge(
        base: {_path: _task(completed: '2026-09-01T00:00:00Z')},
        local: {
          _path: _task(
              title: 'Renamed',
              completed: '2026-09-01T00:00:00Z',
              updated: '2026-11-09T09:00:00Z')
        },
        remote: {archived: _task(completed: '2026-09-01T00:00:00Z')},
      );
      expect(merge.files.keys, [archived]);
      expect(_only(merge).title, 'Renamed');
    });

    test('reopening an archived task brings it back to tasks/', () {
      const archived = 'archive/2026/$_id.md';
      final done = {archived: _task(completed: '2026-09-01T00:00:00Z')};
      final merge = _merge(
        base: done,
        local: {archived: _task(updated: '2026-11-09T09:00:00Z')},
        remote: done,
      );
      expect(merge.files.keys, [_path]);
    });
  });

  group('lists and other files', () {
    const listPath = 'lists/pedals.yaml';

    test('list fields merge key by key', () {
      final merge = _merge(
        base: {listPath: 'id: pedals\nname: Pedals\norder: 1\n'},
        local: {listPath: 'id: pedals\nname: Effects\norder: 1\n'},
        remote: {listPath: 'id: pedals\nname: Pedals\norder: 3\n'},
      );
      expect(_texts(merge)[listPath], 'id: pedals\nname: Effects\norder: 3\n');
    });

    test('a list conflict keeps the remote', () {
      final merge = _merge(
        base: {listPath: 'id: pedals\nname: Pedals\n'},
        local: {listPath: 'id: pedals\nname: Local\n'},
        remote: {listPath: 'id: pedals\nname: Remote\n'},
      );
      expect(_texts(merge)[listPath], 'id: pedals\nname: Remote\n');
      expect(merge.conflicts.single.fields, ['name']);
    });

    test('other files changed on both sides keep the remote', () {
      final merge = _merge(
        base: {'README.md': 'base\n'},
        local: {'README.md': 'local\n'},
        remote: {'README.md': 'remote\n'},
      );
      expect(_texts(merge), {'README.md': 'remote\n'});
      final conflict = merge.conflicts.single;
      expect(conflict.kind, ConflictKind.file);
      expect(conflict.setAside, 'local\n');
    });

    test('a task file that does not parse is merged as a plain file', () {
      const broken = 'tasks/broken.md';
      final merge = _merge(
        base: {broken: 'no frontmatter\n'},
        local: {broken: 'still none\n'},
        remote: {broken: 'none here either\n'},
      );
      expect(_texts(merge), {broken: 'none here either\n'});
      expect(merge.conflicts.single.kind, ConflictKind.file);
    });
  });
}
