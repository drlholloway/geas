import 'package:geas_core/geas_core.dart';

import 'command.dart';
import 'context.dart';
import 'session.dart';

class ListsCommand extends GeasCommand {
  ListsCommand(super.context) {
    argParser.addOption('color',
        help: 'For add: the list color, like #4a90d9.');
  }

  @override
  final name = 'lists';

  @override
  final description = 'Show the lists, or add, rename or remove one.';

  @override
  String get invocation => 'geas lists\n'
      '       geas lists add <name> [--color <#rrggbb>]\n'
      '       geas lists rename <list> <new name>\n'
      '       geas lists rm <list>';

  @override
  Future<int> run() async {
    final color = argResults!['color'] as String?;
    if (color != null && (rest.firstOrNull != 'add')) {
      usageException('--color goes with `geas lists add`.');
    }
    if (color != null && !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
      usageException('Give the color as #rrggbb.');
    }

    final session = await openSession();
    return switch (rest) {
      [] => _show(session),
      ['add', ...final words] when words.isNotEmpty =>
        _add(session, words.join(' '), color),
      ['rename', final list, ...final words] when words.isNotEmpty =>
        _rename(session, list, words.join(' ')),
      ['rm', final list] => _remove(session, list),
      _ => usageException('Unknown or incomplete `geas lists` command.'),
    };
  }

  Future<int> _show(Session session) async {
    await session.pull();
    final counts = _openCounts(session);
    final lists = session.workspace.lists;
    final idWidth = lists.fold(0, (w, l) => l.id.length > w ? l.id.length : w);
    final nameWidth =
        lists.fold(0, (w, l) => l.name.length > w ? l.name.length : w);
    for (final list in lists) {
      final open = counts[list.id] ?? 0;
      out.writeln('  ${list.id.padRight(idWidth)}  '
          '${list.name.padRight(nameWidth)}  $open open');
    }
    return 0;
  }

  Future<int> _add(Session session, String name, String? color) async {
    await session.pull();
    final TaskList list;
    try {
      list = newList(name, session.workspace.lists, color: color);
    } on FormatException catch (e) {
      throw CliException(e.message);
    }
    await session.workspace.saveList(list);
    out.writeln('Added the list ${list.name} (${list.id}).');
    await session.push();
    return 0;
  }

  Future<int> _rename(Session session, String input, String name) async {
    await session.pull();
    final list = session.resolveList(input);
    await session.workspace.saveList(list.copyWith(name: name));
    out.writeln('Renamed ${list.name} to $name.');
    await session.push();
    return 0;
  }

  Future<int> _remove(Session session, String input) async {
    await session.pull();
    final list = session.resolveList(input);
    if (list.id == inboxId) {
      throw const CliException('The inbox can\'t be removed.');
    }
    final now = context.clock();
    final tasks =
        session.workspace.tasks.where((t) => t.list == list.id).toList();
    for (final task in tasks) {
      await session.workspace
          .saveTask(task.copyWith(list: inboxId, updated: now), now: now);
    }
    await session.workspace.deleteList(list.id);
    out.writeln('Removed the list ${list.name}'
        '${tasks.isEmpty ? '' : '; moved ${_tasks(tasks.length)} to the inbox'}.');
    await session.push();
    return 0;
  }

  static Map<String, int> _openCounts(Session session) {
    final counts = <String, int>{};
    for (final task in session.workspace.tasks) {
      if (!task.isCompleted) counts[task.list] = (counts[task.list] ?? 0) + 1;
    }
    return counts;
  }
}

class TagsCommand extends GeasCommand {
  TagsCommand(super.context);

  @override
  final name = 'tags';

  @override
  final description = 'Show the tags on open tasks, with how many use each.';

  @override
  String get invocation => 'geas tags';

  @override
  Future<int> run() async {
    if (rest.isNotEmpty) usageException('tags takes no arguments.');
    final session = await openSession();
    await session.pull();
    final open = session.workspace.tasks.where((t) => !t.isCompleted).toList();
    final tags = allTags(open);
    if (tags.isEmpty) {
      out.writeln('No tags.');
      return 0;
    }
    final width = tags.fold(0, (w, t) => t.length > w ? t.length : w) + 1;
    for (final tag in tags) {
      final lower = tag.toLowerCase();
      final count =
          open.where((t) => t.tags.any((x) => x.toLowerCase() == lower)).length;
      out.writeln('  ${'#$tag'.padRight(width)}  $count');
    }
    return 0;
  }
}

class SyncCommand extends GeasCommand {
  SyncCommand(super.context);

  @override
  final name = 'sync';

  @override
  final description = 'Pull, merge and push now. Other commands do this on '
      'their own unless given --offline.';

  @override
  String get invocation => 'geas sync';

  @override
  Future<int> run() async {
    if (rest.isNotEmpty) usageException('sync takes no arguments.');
    if (offline) usageException('sync can\'t run --offline.');
    final session = await openSession();
    final result = await session.sync();
    final pushed = [
      if (result.added > 0) '${result.added} added',
      if (result.updated > 0) '${result.updated} updated',
      if (result.moved > 0) '${result.moved} moved',
      if (result.removed > 0) '${result.removed} removed',
    ];
    if (result.pulled == 0 && pushed.isEmpty) {
      out.writeln('Already up to date.');
    } else {
      if (result.pulled > 0) {
        out.writeln('Pulled ${result.pulled} '
            '${result.pulled == 1 ? 'change' : 'changes'}.');
      }
      if (pushed.isNotEmpty) out.writeln('Pushed: ${pushed.join(', ')}.');
    }
    return 0;
  }
}

String _tasks(int n) => n == 1 ? '1 task' : '$n tasks';
