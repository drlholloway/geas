import 'dart:io';

import 'package:geas_core/geas_core.dart';
import 'package:test/test.dart';

import 'harness.dart';

void main() {
  late Harness geas;

  setUp(() async {
    geas = await Harness.create();
    await geas.init();
  });
  tearDown(() => geas.dispose());

  /// Adds a task and returns its short id.
  Future<String> add(List<String> args) async {
    expect(await geas(['add', ...args]), 0, reason: '${geas.err}');
    return RegExp(r'^Added (\S+) ').firstMatch('${geas.out}')![1]!;
  }

  group('add', () {
    test('adds to the inbox and pushes', () async {
      await add(['Buy', 'milk']);
      expect(geas.out.toString(), endsWith('Buy milk.\n'));
      final task = geas.remoteTask('Buy milk');
      expect(task.list, inboxId);
      expect(task.created, geas.now.toUtc());
      expect(geas.github.commits.last, 'sync(testbox): 1 added');
    });

    test('sets list, tags, due and priority', () async {
      expect(await geas(['lists', 'add', 'Pedal', 'builds']), 0);
      await add([
        'Order 1N914s', '-l', 'pedal builds', '-t', '#tayda,pedals', //
        '-t', 'parts', '-d', 'fri 5pm', '-p', 'h',
      ]);
      expect(geas.out.toString(), contains('due Fri 17:00'));
      final task = geas.remoteTask('Order 1N914s');
      expect(task.list, 'pedal-builds');
      expect(task.tags, ['tayda', 'pedals', 'parts']);
      expect(task.due!.date, const LocalDate(2026, 11, 13));
      expect(task.due!.instant!.isAtSameMomentAs(DateTime(2026, 11, 13, 17)),
          isTrue);
      expect(task.priority, Priority.high);
    });

    test('refuses an unknown list', () async {
      expect(await geas(['add', 'x', '-l', 'nope']), 1);
      expect(geas.err.toString(), contains('No list "nope"'));
      expect(geas.github.files.keys, [repoConfigPath]);
    });

    test('refuses a bad due date or priority', () async {
      expect(await geas(['add', 'x', '-d', 'someday']), 64);
      expect(await geas(['add', 'x', '-p', 'urgent']), 64);
      expect(await geas(['add']), 64);
    });
  });

  group('ls', () {
    setUp(() async {
      await add(['Late', '-d', '2026-11-08']);
      await add(['Now', '-d', 'today', '-p', 'high', '-t', 'home']);
      await add(['Friday', '-d', 'fri']);
      await add(['Later', '-d', '2026-12-25']);
      await add(['Whenever', '-t', 'home']);
    });

    String titles() => RegExp(r'^  \S+.*?\b(Late|Now|Friday|Later|Whenever)\b',
            multiLine: true)
        .allMatches('${geas.out}')
        .map((m) => m[1])
        .join(' ');

    test('groups open tasks by when they are due', () async {
      expect(await geas(['ls']), 0);
      final out = '${geas.out}';
      expect(titles(), 'Late Now Friday Later Whenever');
      expect(
          RegExp(r'^\S.*$', multiLine: true)
              .allMatches(out)
              .map((m) => m[0])
              .toList(),
          ['Overdue', 'Today', 'Upcoming', 'No date']);
      expect(out, contains('yesterday'));
      expect(out, contains('!!!  Now  #home'));
    });

    test('filters by window, tag and list', () async {
      expect(await geas(['ls', '--today']), 0);
      expect(titles(), 'Late Now');
      expect(await geas(['ls', '--overdue']), 0);
      expect(titles(), 'Late');
      expect(await geas(['ls', '--week']), 0);
      expect(titles(), 'Late Now Friday');
      expect(await geas(['ls', '-t', '#HOME']), 0);
      expect(titles(), 'Now Whenever');
      expect(await geas(['ls', '-l', 'inbox']), 0);
      expect(titles(), 'Late Now Friday Later Whenever');
      expect(await geas(['ls', '--today', '--week']), 64);
    });

    test('--done lists completed tasks', () async {
      expect(await geas(['ls', '--done']), 0);
      expect('${geas.out}', 'No completed tasks.\n');
      expect(await geas(['ls']), 0);
      final id = RegExp(r'^  (\S+) .*Friday', multiLine: true)
          .firstMatch('${geas.out}')![1]!;
      expect(await geas(['done', id]), 0);
      expect(await geas(['ls', '--done']), 0);
      expect('${geas.out}', contains('done 2026-11-09'));
      expect(titles(), 'Friday');
    });
  });

  test('show prints every field and the notes', () async {
    final id = await add(['Order parts', '-d', 'tomorrow 9:00', '-t', 'x']);
    expect(await geas(['show', id]), 0);
    final out = '${geas.out}';
    expect(out, startsWith('Order parts\n'));
    expect(out, contains('  due       Tue 2026-11-10 09:00 (tomorrow 09:00)'));
    expect(out, contains('  tags      #x'));
    expect(out, contains('  list      Inbox'));
  });

  group('done', () {
    test('marks done and pushes, and --undo reopens', () async {
      final id = await add(['Buy milk']);
      geas.now = geas.now.add(const Duration(minutes: 5));
      expect(await geas(['done', id]), 0);
      expect('${geas.out}', 'Done: $id Buy milk\n');
      expect(geas.remoteTask('Buy milk').completed, geas.now.toUtc());

      expect(await geas(['done', id]), 0);
      expect('${geas.out}', contains('already done'));

      expect(await geas(['done', '--undo', id]), 0);
      expect(geas.remoteTask('Buy milk').isCompleted, isFalse);
    });

    test('changes nothing if any id is unknown', () async {
      final id = await add(['Buy milk']);
      expect(await geas(['done', id, 'ZZZZ']), 1);
      expect(geas.err.toString(), contains('No task matches "ZZZZ"'));
      expect(geas.remoteTask('Buy milk').isCompleted, isFalse);
    });

    test('an ambiguous id lists the matches', () async {
      geas.pushTask('01AAAAAAAAAAAAAAAAAAAAAA01', 'One');
      geas.pushTask('01AAAAAAAAAAAAAAAAAAAAAB01', 'Two');
      expect(await geas(['done', '01']), 1);
      expect(geas.err.toString(), contains('matches more than one task'));
    });
  });

  test('rm deletes from GitHub', () async {
    final id = await add(['Buy milk']);
    expect(await geas(['rm', id]), 0);
    expect('${geas.out}', 'Removed $id Buy milk\n');
    expect(geas.github.files.keys, [repoConfigPath]);
  });

  group('edit', () {
    late String id;

    setUp(() async {
      geas.pushTask('01AAAAAAAAAAAAAAAAAAAAAAAA', 'Buy milk',
          extra: 'store: corner  # mine\n');
      id = 'AAAA';
      expect(await geas(['sync']), 0);
    });

    void editWith(String Function(String text) change) =>
        geas.editor = (path) async {
          final file = File(path);
          await file.writeAsString(change(await file.readAsString()));
          return true;
        };

    test('saves a valid edit, keeping what Geas does not know', () async {
      editWith(
          (t) => '${t.replaceFirst('title: Buy milk', 'title: Buy oat milk')}'
              '- [ ] two cartons\n');
      expect(await geas(['edit', id]), 0, reason: '${geas.err}');
      expect('${geas.out}', 'Saved $id Buy oat milk\n');
      final text = geas.remote('tasks/01AAAAAAAAAAAAAAAAAAAAAAAA.md')!;
      expect(text, contains('store: corner  # mine'));
      expect(text, contains('- [ ] two cartons'));
      expect(Task.parse(text).updated, geas.now.toUtc());
    });

    test('no change, no save', () async {
      final commits = geas.github.commits.length;
      expect(await geas(['edit', id]), 0);
      expect('${geas.out}', 'No changes.\n');
      expect(geas.github.commits, hasLength(commits));
    });

    test('an invalid edit is refused, and kept on request', () async {
      editWith((t) => t.replaceFirst('title: Buy milk\n', ''));
      expect(await geas(['edit', id]), 1);
      expect(geas.err.toString(), contains('"title"'));
      final kept = RegExp(r'Your edit is in (\S+)\.$', multiLine: true)
          .firstMatch('${geas.err}')![1]!;
      expect(File(kept).existsSync(), isTrue);
      expect(geas.remoteTask('Buy milk').title, 'Buy milk');
      await File(kept).parent.delete(recursive: true);
    });

    test('a second try can fix it', () async {
      var tries = 0;
      geas.confirmAnswer = true;
      editWith((t) => ++tries == 1
          ? t.replaceFirst('id: 01AAAAAAAAAAAAAAAAAAAAAAAA', 'id: other')
          : t
              .replaceFirst('id: other', 'id: 01AAAAAAAAAAAAAAAAAAAAAAAA')
              .replaceFirst('Buy milk', 'Buy bread'));
      expect(await geas(['edit', id]), 0);
      expect(geas.err.toString(), contains('The id has to stay'));
      expect(geas.remoteTask('Buy bread').id, '01AAAAAAAAAAAAAAAAAAAAAAAA');
    });
  });

  group('sync', () {
    test('pulls tasks from other devices', () async {
      expect(await geas(['sync']), 0);
      expect('${geas.out}', 'Already up to date.\n');
      geas.pushTask('01BBBBBBBBBBBBBBBBBBBBBBBB', 'From the phone');
      expect(await geas(['sync']), 0);
      expect('${geas.out}', 'Pulled 1 change.\n');
      expect(await geas(['ls', '--offline']), 0);
      expect('${geas.out}', contains('From the phone'));
    });

    test('--offline keeps changes local until the next sync', () async {
      final before = geas.connections.length;
      await add(['Offline task', '--offline']);
      expect(geas.connections, hasLength(before));
      expect(geas.github.files.keys, [repoConfigPath]);

      expect(await geas(['sync']), 0);
      expect('${geas.out}', 'Pushed: 1 added.\n');
      expect(geas.remoteTask('Offline task').title, 'Offline task');
      expect(await geas(['sync', '--offline']), 64);
    });

    test('without a network, commands warn and use the local copy', () async {
      geas.client = UnreachableGitHub();
      await add(['Buy milk']);
      expect(geas.err.toString(), contains('Couldn\'t reach GitHub'));
      expect(geas.err.toString(), contains('next sync'));
      expect(await geas(['ls']), 0);
      expect('${geas.out}', contains('Buy milk'));
      expect(await geas(['sync']), 1);
      expect(geas.err.toString(), 'geas: Couldn\'t reach GitHub.\n');

      geas.client = null;
      expect(await geas(['sync']), 0);
      expect(geas.remoteTask('Buy milk').title, 'Buy milk');
    });
  });
}
