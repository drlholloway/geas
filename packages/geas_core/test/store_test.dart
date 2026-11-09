import 'dart:convert';
import 'dart:io';

import 'package:geas_core/geas_core.dart';
import 'package:geas_core/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() async => tmp = await Directory.systemTemp.createTemp('geas_store'));
  tearDown(() => tmp.delete(recursive: true));

  group('DirectoryArea', () {
    test('writes, lists and deletes nested files', () async {
      final area = DirectoryArea(p.join(tmp.path, 'working'));
      expect(await area.readAll(), isEmpty);

      await area.write('geas.yaml', utf8.encode('format: 1\n'));
      await area.write('archive/2026/a.md', utf8.encode('a'));
      await area.write('archive/2026/a.md', utf8.encode('a2'));
      final files = await area.readAll();
      expect(files.keys, unorderedEquals(['geas.yaml', 'archive/2026/a.md']));
      expect(utf8.decode(files['archive/2026/a.md']!), 'a2');

      await area.delete('archive/2026/a.md');
      await area.delete('missing.md');
      expect((await area.readAll()).keys, ['geas.yaml']);
      expect(Directory(p.join(tmp.path, 'working', 'archive')).existsSync(),
          isFalse);
    });

    test('leaves no temporary files behind and ignores stray ones', () async {
      final area = DirectoryArea(tmp.path);
      await area.write('tasks/a.md', utf8.encode('a'));
      File(p.join(tmp.path, 'tasks', 'b.md.123.geas-tmp'))
          .writeAsStringSync('x');
      expect((await area.readAll()).keys, ['tasks/a.md']);
      final names = Directory(p.join(tmp.path, 'tasks'))
          .listSync()
          .map((e) => p.basename(e.path));
      expect(names.where((n) => n.startsWith('a.md.')), isEmpty);
    });

    for (final bad in ['../escape.md', '/abs.md', 'a/../../b', r'a\b', '']) {
      test('refuses the path "$bad"', () async {
        expect(
            () => DirectoryArea(tmp.path).write(bad, [1]), throwsArgumentError);
      });
    }
  });

  group('DirectoryStore', () {
    test('keeps the base commit and conflicts across instances', () async {
      final store = DirectoryStore(tmp.path);
      expect(await store.readBaseCommit(), isNull);
      expect(await store.readConflicts(), isEmpty);

      await store.writeBaseCommit('abc123');
      final conflict = SyncConflict(
        key: 'id',
        path: 'tasks/id.md',
        kind: ConflictKind.fields,
        detected: DateTime.utc(2026, 11, 9),
        fields: const ['title'],
        keptLocal: true,
        setAside: '---\n...',
      );
      await store.writeConflicts([conflict]);

      final again = DirectoryStore(tmp.path);
      expect(await again.readBaseCommit(), 'abc123');
      final read = (await again.readConflicts()).single;
      expect(read.toJson(), conflict.toJson());
      // Metadata stays out of the synced areas.
      expect(await again.working.readAll(), isEmpty);
      expect(await again.base.readAll(), isEmpty);
    });

    test('syncs end to end on disk', () async {
      final github = FakeGitHubClient();
      await initDataRepo(github);
      final store = DirectoryStore(tmp.path);
      final now = DateTime.utc(2026, 11, 9);
      final syncer =
          Syncer(github: github, store: store, device: 'mac', clock: () => now);

      await syncer.sync();
      final ws = await Workspace.load(store.working);
      await ws.saveTask(Task.create(title: 'On disk', now: now), now: now);
      final result = await syncer.sync();

      expect(result.added, 1);
      expect(await store.readBaseCommit(), github.head);
      expect((await store.base.readAll()).length, 2);
    });
  });

  group('Workspace', () {
    final now = DateTime.utc(2026, 11, 9);

    test('indexes tasks and lists and reports files it cannot read', () async {
      final area = MemoryArea();
      final task = Task.create(title: 'One', now: now);
      area.files.addAll({
        'tasks/${task.id}.md': utf8.encode(task.encode()),
        'lists/home.yaml': utf8.encode('id: home\nname: Home\n'),
        'tasks/broken.md': utf8.encode('no frontmatter'),
        'lists/bad.yaml': utf8.encode('name: no id\n'),
        'README.md': utf8.encode('ignored'),
      });
      final ws = await Workspace.load(area);
      expect(ws.task(task.id)?.title, 'One');
      expect(ws.lists.map((l) => l.id), [inboxId, 'home']);
      expect(ws.problems.keys,
          unorderedEquals(['tasks/broken.md', 'lists/bad.yaml']));
    });

    test('saving moves a task between tasks/ and archive/', () async {
      final area = MemoryArea();
      final ws = await Workspace.load(area);
      final task =
          await ws.saveTask(Task.create(title: 'T', now: now), now: now);
      expect(area.files.keys, ['tasks/${task.id}.md']);

      final done = task.complete(DateTime.utc(2026, 9, 1));
      await ws.saveTask(done, now: now);
      expect(area.files.keys, ['archive/2026/${task.id}.md']);

      await ws.saveTask(done.reopen(now), now: now);
      expect(area.files.keys, ['tasks/${task.id}.md']);
    });

    test('a saved task keeps its frontmatter for the next edit', () async {
      final area = MemoryArea();
      final ws = await Workspace.load(area);
      final saved =
          await ws.saveTask(Task.create(title: 'T', now: now), now: now);
      expect(saved.frontmatter, isNotNull);
    });

    test('deletes tasks and lists, and reloads', () async {
      final area = MemoryArea();
      final ws = await Workspace.load(area);
      final task =
          await ws.saveTask(Task.create(title: 'T', now: now), now: now);
      await ws.saveList(const TaskList(id: 'home', name: 'Home'));
      expect(area.files.keys, hasLength(2));

      await ws.deleteTask(task.id);
      await ws.deleteList('home');
      expect(area.files, isEmpty);
      expect(ws.tasks, isEmpty);

      area.files['lists/x.yaml'] = utf8.encode('id: x\nname: X\n');
      await ws.reload();
      expect(ws.lists.map((l) => l.id), [inboxId, 'x']);
    });
  });

  test('gitBlobSha matches git hash-object', () {
    // printf 'hello\n' | git hash-object --stdin
    expect(gitBlobSha(utf8.encode('hello\n')),
        'ce013625030ba8dba906f756967f9e9ca394464a');
    expect(gitBlobSha([]), 'e69de29bb2d1d6434b8b29ae775ad8c2e48c5391');
  });

  test('MemoryTokenStore', () async {
    final tokens = MemoryTokenStore();
    const repo = RepoRef('drl', 'geas-data');
    expect(await tokens.read(repo), isNull);
    await tokens.write(repo, 'tok');
    expect(await tokens.read(repo), 'tok');
    await tokens.delete(repo);
    expect(await tokens.read(repo), isNull);
  });
}
