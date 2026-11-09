import 'dart:convert';

import 'package:geas_core/geas_core.dart';
import 'package:geas_core/testing.dart';
import 'package:test/test.dart';

var _now = DateTime.utc(2026, 11, 9, 12);

/// One simulated device: its own store, syncing with the shared fake.
class _Device {
  _Device(this.name, this.github);

  final String name;
  final FakeGitHubClient github;
  final store = MemoryStore();

  late final _syncer = Syncer(
    github: github,
    store: store,
    device: name,
    clock: () => _now,
  );

  Future<SyncResult> sync() => _syncer.sync();

  Future<Workspace> workspace() => Workspace.load(store.working);

  Future<Task> add(String title) async {
    final ws = await workspace();
    return ws.saveTask(Task.create(title: title, now: _now), now: _now);
  }

  Future<Task> edit(String id, Task Function(Task) change) async {
    final ws = await workspace();
    return ws.saveTask(change(ws.task(id)!), now: _now);
  }

  Future<Task> task(String id) async => (await workspace()).task(id)!;

  Map<String, String> get working => store.working.files
      .map((path, bytes) => MapEntry(path, utf8.decode(bytes)));
}

Map<String, String> _texts(Map<String, List<int>> files) =>
    files.map((path, bytes) => MapEntry(path, utf8.decode(bytes)));

void _tick([Duration by = const Duration(minutes: 1)]) => _now = _now.add(by);

void main() {
  late FakeGitHubClient github;
  late _Device laptop, phone;

  setUp(() async {
    _now = DateTime.utc(2026, 11, 9, 12);
    github = FakeGitHubClient();
    await initDataRepo(github);
    laptop = _Device('laptop', github);
    phone = _Device('phone', github);
  });

  test('an empty repo needs geas init first', () async {
    final device = _Device('laptop', FakeGitHubClient());
    await expectLater(device.sync(), throwsA(isA<NotInitializedException>()));
  });

  test('a repo without geas.yaml needs geas init first', () async {
    final other = FakeGitHubClient()..push({'README.md': utf8.encode('hi\n')});
    await expectLater(_Device('laptop', other).sync(),
        throwsA(isA<NotInitializedException>()));
  });

  test('the first sync pulls the repo and pushes nothing', () async {
    final result = await laptop.sync();
    expect(result.pushed, isFalse);
    expect(result.pulled, 1);
    expect(laptop.working, {'geas.yaml': 'format: 1\n'});
    expect(laptop.store.baseCommit, github.head);
    expect(github.commits, ['geas init']);
  });

  test('a task added on one device reaches the other', () async {
    await laptop.sync();
    await phone.sync();
    final task = await laptop.add('Order 1N914s');

    final pushed = await laptop.sync();
    expect(pushed.added, 1);
    expect(github.commits.last, 'sync(laptop): 1 added');

    await phone.sync();
    expect((await phone.task(task.id)).title, 'Order 1N914s');
    expect(phone.working, laptop.working);
  });

  test('a sync with nothing to do makes no commit', () async {
    await laptop.sync();
    final head = github.head;
    final result = await laptop.sync();
    expect(result.pushed, isFalse);
    expect(result.pulled, 0);
    expect(github.head, head);
  });

  test('edits to different fields on two devices both survive', () async {
    await laptop.sync();
    final task = await laptop.add('Order diodes');
    await laptop.sync();
    await phone.sync();

    _tick();
    await laptop.edit(
        task.id, (t) => t.copyWith(title: 'Order 1N4148s', updated: _now));
    _tick();
    await phone.edit(
        task.id, (t) => t.copyWith(priority: Priority.high, updated: _now));

    await laptop.sync();
    final merged = await phone.sync();
    expect(merged.conflicts, isEmpty);
    expect(merged.updated, 1);
    await laptop.sync();

    for (final device in [laptop, phone]) {
      final t = await device.task(task.id);
      expect(t.title, 'Order 1N4148s');
      expect(t.priority, Priority.high);
    }
    expect(laptop.working, phone.working);
    expect(laptop.working, _texts(github.files));
  });

  test('the same field edited on both: the newer wins, the other is kept',
      () async {
    await laptop.sync();
    final task = await laptop.add('Diodes');
    await laptop.sync();
    await phone.sync();

    _tick();
    await phone.edit(task.id, (t) => t.copyWith(title: 'Older', updated: _now));
    _tick();
    await laptop.edit(
        task.id, (t) => t.copyWith(title: 'Newer', updated: _now));

    await laptop.sync();
    final result = await phone.sync();
    expect((await phone.task(task.id)).title, 'Newer');
    expect(result.conflicts.single.fields, ['title']);
    expect(phone.store.conflicts.single.setAside, contains('title: Older'));
  });

  test('a device that loses the race retries and includes both', () async {
    await laptop.sync();
    await phone.sync();
    await phone.add('From the phone');
    await laptop.add('From the laptop');

    var raced = false;
    github.beforeUpdateBranch = () async {
      if (raced) return;
      raced = true;
      github.beforeUpdateBranch = null;
      await phone.sync(); // lands between the laptop's read and write
    };
    await laptop.sync();

    expect(github.commits, [
      'geas init',
      'sync(phone): 1 added',
      'sync(laptop): 1 added',
    ]);
    expect((await laptop.workspace()).tasks.map((t) => t.title),
        unorderedEquals(['From the phone', 'From the laptop']));
  });

  test('giving up after repeated races changes nothing locally', () async {
    await laptop.sync();
    await laptop.add('Never lands');
    final before = Map.of(laptop.store.working.files);
    final baseCommit = laptop.store.baseCommit;

    var n = 0;
    github.beforeUpdateBranch =
        () async => github.push({'other-${n++}.txt': utf8.encode('x')});

    await expectLater(
        laptop.sync(), throwsA(isA<SyncRetriesExhaustedException>()));
    expect(laptop.store.working.files, before);
    expect(laptop.store.baseCommit, baseCommit);
  });

  test('downloads only the files that changed', () async {
    await laptop.sync();
    for (var i = 0; i < 5; i++) {
      await laptop.add('Task $i');
    }
    await laptop.sync();
    await phone.sync();

    final one = (await phone.workspace()).tasks.first;
    _tick();
    await phone.edit(one.id, (t) => t.complete(_now));
    await phone.sync();

    github.blobReads = 0;
    final result = await laptop.sync();
    expect(result.pulled, 1);
    expect(github.blobReads, 1);
  });

  test('an edit made while a sync runs is kept for the next sync', () async {
    await laptop.sync();
    await laptop.add('Before');
    github.beforeUpdateBranch = () async {
      github.beforeUpdateBranch = null;
      await laptop.add('During');
    };
    await laptop.sync();

    final titles = (await laptop.workspace()).tasks.map((t) => t.title);
    expect(titles, unorderedEquals(['Before', 'During']));
    expect(github.files.length, 2); // geas.yaml and "Before"

    final next = await laptop.sync();
    expect(next.added, 1);
    expect(github.files.length, 3);
  });

  test('a hand edit on GitHub merges with a local edit', () async {
    await laptop.sync();
    final task = await laptop.add('Diodes');
    await laptop.sync();

    final path = 'tasks/${task.id}.md';
    final handEdited = utf8
        .decode(github.files[path]!)
        .replaceFirst('---\n', '---\n# added on github.com\n')
        .replaceFirst('completed: null\n', 'completed: null\nmood: keen\n');
    github.push({path: utf8.encode(handEdited)}, message: 'Edit on GitHub');

    _tick();
    await laptop.edit(
        task.id, (t) => t.copyWith(priority: Priority.low, updated: _now));
    final result = await laptop.sync();

    expect(result.conflicts, isEmpty);
    final text = laptop.working[path]!;
    expect(text, contains('# added on github.com'));
    expect(text, contains('mood: keen'));
    expect(text, contains('priority: low'));
    expect(_texts(github.files)[path], text);
  });

  test('tasks done over 30 days ago are archived by sync', () async {
    await laptop.sync();
    final task = await laptop.add('Old news');
    await laptop.edit(task.id, (t) => t.complete(_now));
    await laptop.sync();

    _tick(const Duration(days: 31));
    final result = await laptop.sync();
    expect(result.moved, 1);
    expect(github.commits.last, 'sync(laptop): 1 moved');
    expect(github.files.keys, contains('archive/2026/${task.id}.md'));
    expect(github.files.keys, isNot(contains('tasks/${task.id}.md')));
  });

  test('deleting a task removes it everywhere', () async {
    await laptop.sync();
    final task = await laptop.add('Delete me');
    await laptop.sync();
    await phone.sync();

    await (await phone.workspace()).deleteTask(task.id);
    final result = await phone.sync();
    expect(result.removed, 1);
    await laptop.sync();
    expect((await laptop.workspace()).task(task.id), isNull);
  });

  test('refuses a repo in a newer format', () async {
    await laptop.sync();
    github.push({repoConfigPath: utf8.encode('format: 2\n')});
    await expectLater(
        laptop.sync(), throwsA(isA<UnsupportedFormatException>()));
  });
}
