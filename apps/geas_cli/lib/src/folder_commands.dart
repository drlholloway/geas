import 'package:geas_core/geas_core.dart';

import 'command.dart';
import 'context.dart';
import 'session.dart';

/// Something a folder can hold.
typedef _Item = ({String kind, String id, String name, String? folder});

class FoldersCommand extends GeasCommand {
  FoldersCommand(super.context);

  @override
  final name = 'folders';

  @override
  final description = 'Show the folders and what\'s in them, or add, rename '
      'or remove one, or put lists, filters and trackers in one. Name an '
      'item by its id or name; if two kinds share a name, say which: '
      'list:pedals, filter:late, tracker:metformin.';

  @override
  String get invocation => 'geas folders\n'
      '       geas folders add <name>\n'
      '       geas folders rename <folder> <new name>\n'
      '       geas folders rm <folder>\n'
      '       geas folders nest <folder> <inside>\n'
      '       geas folders unnest <folder>\n'
      '       geas folders move <folder> <position>\n'
      '       geas folders put <folder> <item>...\n'
      '       geas folders take <item>...';

  @override
  Future<int> run() async {
    final session = await openSession();
    await session.pull();
    return switch (rest) {
      [] => _show(session),
      ['add', ...final words] when words.isNotEmpty =>
        _add(session, words.join(' ')),
      ['rename', final folder, ...final words] when words.isNotEmpty =>
        _rename(session, folder, words.join(' ')),
      ['rm', ...final words] when words.isNotEmpty =>
        _remove(session, words.join(' ')),
      ['nest', final folder, final inside] =>
        _nest(session, _resolve(session, folder), _resolve(session, inside)),
      ['unnest', final folder] =>
        _nest(session, _resolve(session, folder), null),
      ['move', final folder, final position] =>
        _move(session, _resolve(session, folder), position),
      ['put', final folder, ...final items] when items.isNotEmpty =>
        _put(session, _resolve(session, folder), items),
      ['take', ...final items] when items.isNotEmpty =>
        _put(session, null, items),
      _ => usageException('Unknown or incomplete `geas folders` command.'),
    };
  }

  /// Everything that can go in a folder.
  static List<_Item> _items(Workspace w) => [
        for (final l in w.lists)
          if (l.id != inboxId)
            (kind: 'list', id: l.id, name: l.name, folder: l.folder),
        for (final f in w.filters)
          (kind: 'filter', id: f.id, name: f.name, folder: f.folder),
        for (final t in w.trackers)
          (kind: 'tracker', id: t.id, name: t.name, folder: t.folder),
      ];

  /// The folder [input] names, by id or name, ignoring case.
  static Folder _resolve(Session session, String input) {
    final folders = session.workspace.folders;
    final lower = input.trim().toLowerCase();
    for (final f in folders) {
      if (f.id.toLowerCase() == lower || f.name.toLowerCase() == lower) {
        return f;
      }
    }
    throw CliException(folders.isEmpty
        ? 'No folders yet. Add one with `geas folders add <name>`.'
        : 'No folder "$input". The folders are: '
            '${folders.map((f) => f.id).join(', ')}.');
  }

  /// The list, filter or tracker [input] names.
  static _Item _item(Session session, String input) {
    final colon = input.indexOf(':');
    final kind = colon > 0 ? input.substring(0, colon).toLowerCase() : null;
    final kinds = const ['list', 'filter', 'tracker'];
    final qualified = kinds.contains(kind);
    final wanted =
        (qualified ? input.substring(colon + 1) : input).trim().toLowerCase();
    final found = _items(session.workspace)
        .where((i) =>
            (!qualified || i.kind == kind) &&
            (i.id.toLowerCase() == wanted || i.name.toLowerCase() == wanted))
        .toList();
    if (found.length == 1) return found.single;
    if (found.isEmpty) {
      throw CliException('No list, filter or tracker is called "$input".');
    }
    throw CliException(
        '"$input" is ${found.map((i) => 'a ${i.kind}').join(' and ')}. '
        'Say which: ${found.map((i) => '${i.kind}:${i.id}').join(' or ')}.');
  }

  Future<int> _show(Session session) async {
    final w = session.workspace;
    if (w.folders.isEmpty) {
      out.writeln('No folders yet. Add one with `geas folders add <name>`.');
      return 0;
    }
    final items = _items(w);
    final tree = folderTree(w.folders);
    for (final (index, (:folder, :depth)) in tree.indexed) {
      final pad = '  ' * depth;
      out.writeln('$pad${folder.name} (${folder.id})');
      final inside = items.where((i) => i.folder == folder.id);
      final hasFolders =
          index + 1 < tree.length && tree[index + 1].depth > depth;
      if (inside.isEmpty && !hasFolders) out.writeln('$pad  (empty)');
      for (final i in inside) {
        out.writeln('$pad  ${i.kind.padRight(7)}  ${i.name}');
      }
    }
    return 0;
  }

  /// Puts [folder] inside [inside], or at the top level if that's null.
  Future<int> _nest(Session session, Folder folder, Folder? inside) async {
    final all = session.workspace.folders;
    if (inside != null &&
        (inside.id == folder.id ||
            foldersInside(folder.id, all).contains(inside.id))) {
      throw CliException(
          '${inside.name} is ${inside.id == folder.id ? '' : 'inside '}'
          '${folder.name}${inside.id == folder.id ? ' itself' : ''}; '
          'a folder can\'t go inside itself.');
    }
    await session.workspace.saveFolder(folder.copyWith(parent: inside?.id));
    out.writeln(inside == null
        ? '${folder.name} is at the top level.'
        : 'Put ${folder.name} inside ${inside.name}.');
    await session.push();
    return 0;
  }

  /// Moves [folder] to [position] among the folders at its level.
  Future<int> _move(Session session, Folder folder, String position) async {
    final place = int.tryParse(position);
    if (place == null || place < 1) {
      usageException('Give the position as a number; 1 is first.');
    }
    final all = session.workspace.folders;
    final parent = parentFolder(folder, all)?.id;
    final siblings = sortFolders(all
        .where((f) => f.id != folder.id && parentFolder(f, all)?.id == parent));
    siblings.insert((place - 1).clamp(0, siblings.length), folder);
    for (final f in renumberFolders(siblings)) {
      await session.workspace.saveFolder(f);
    }
    out.writeln(siblings.map((f) => f.name).join(', '));
    await session.push();
    return 0;
  }

  Future<int> _add(Session session, String name) async {
    final Folder folder;
    try {
      folder = newFolder(name, session.workspace.folders);
    } on FormatException catch (e) {
      throw CliException(e.message);
    }
    await session.workspace.saveFolder(folder);
    out.writeln('Added the folder ${folder.name} (${folder.id}).');
    await session.push();
    return 0;
  }

  Future<int> _rename(Session session, String input, String name) async {
    final folder = _resolve(session, input);
    await session.workspace.saveFolder(folder.copyWith(name: name));
    out.writeln('Renamed ${folder.name} to $name.');
    await session.push();
    return 0;
  }

  Future<int> _remove(Session session, String input) async {
    final folder = _resolve(session, input);
    final inside =
        _items(session.workspace).where((i) => i.folder == folder.id).length;
    await session.workspace.deleteFolder(folder.id);
    out.writeln('Removed the folder ${folder.name}'
        '${inside == 0 ? '' : '; what was in it ($inside) is in no folder now'}.');
    await session.push();
    return 0;
  }

  /// Puts each of [inputs] in [folder], or in none if it's null.
  Future<int> _put(Session session, Folder? folder, List<String> inputs) async {
    final w = session.workspace;
    final items = [for (final input in inputs) _item(session, input)];
    for (final item in items) {
      switch (item.kind) {
        case 'list':
          final list = w.lists.firstWhere((l) => l.id == item.id);
          await w.saveList(list.copyWith(folder: folder?.id));
        case 'filter':
          final filter = w.filters.firstWhere((f) => f.id == item.id);
          await w.saveFilter(filter.copyWith(folder: folder?.id));
        default:
          await w.saveTracker(w.tracker(item.id)!.copyWith(folder: folder?.id));
      }
      out.writeln(folder == null
          ? 'Took ${item.name} out of its folder.'
          : 'Put ${item.name} in ${folder.name}.');
    }
    await session.push();
    return 0;
  }
}
