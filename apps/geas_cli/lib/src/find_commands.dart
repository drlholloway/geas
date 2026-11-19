import 'package:geas_core/geas_core.dart';

import 'command.dart';
import 'context.dart';
import 'output.dart';
import 'session.dart';

/// The saved filter [input] names, by id or name, ignoring case.
SavedFilter resolveFilter(Session session, String input) {
  final filters = session.workspace.filters;
  final lower = input.trim().toLowerCase();
  for (final f in filters) {
    if (f.id.toLowerCase() == lower || f.name.toLowerCase() == lower) return f;
  }
  throw CliException(filters.isEmpty
      ? 'No filters saved yet. Save one with '
          '`geas find --save <name> <query>`.'
      : 'No filter "$input". The filters are: '
          '${filters.map((f) => f.id).join(', ')}.');
}

class FindCommand extends GeasCommand {
  FindCommand(super.context) {
    argParser
      ..addOption('save', help: 'Keep this search as a filter with this name.')
      ..addOption('filter',
          abbr: 'f', help: 'Run a saved filter, by id or name.');
  }

  @override
  final name = 'find';

  @override
  final aliases = const ['search'];

  @override
  final description = 'Find tasks. Words must all be in the title or notes; '
      '#tag, ^list and !high narrow it; due:today, due:week, due:overdue, '
      'due:none or due:any pick by due date; is:done or is:all look past '
      'open tasks.';

  @override
  String get invocation => 'geas find <query>... [--save <name>]\n'
      '       geas find -f <filter>';

  @override
  Future<int> run() async {
    final args = argResults!;
    final saveAs = args['save'] as String?;
    final filterName = args['filter'] as String?;
    var text = rest.join(' ').trim();
    if (filterName == null && text.isEmpty) {
      usageException('Say what to find, or name a filter with -f.');
    }
    if (filterName != null && (text.isNotEmpty || saveAs != null)) {
      usageException('-f runs a saved filter as it is.');
    }

    final session = await openSession();
    await session.pull();
    final workspace = session.workspace;
    if (filterName != null) text = resolveFilter(session, filterName).query;

    if (saveAs != null) {
      final SavedFilter filter;
      try {
        filter = newFilter(saveAs, text, workspace.filters);
      } on FormatException catch (e) {
        throw CliException(e.message);
      }
      await workspace.saveFilter(filter);
      out.writeln('Saved the filter ${filter.name} (${filter.id}).');
    }

    final now = context.clock();
    final found = TaskQuery.parse(text, lists: workspace.lists)
        .search(workspace.tasks, now);
    if (found.isEmpty) {
      out.writeln('No tasks match.');
    } else {
      taskRows(
        found,
        now: now,
        shortId: session.shortId,
        when: (t) => t.isCompleted
            ? 'done'
            : t.due == null
                ? ''
                : dueLabel(t.due!, now),
      ).forEach(out.writeln);
    }
    if (saveAs != null) await session.push();
    return 0;
  }
}

class FiltersCommand extends GeasCommand {
  FiltersCommand(super.context);

  @override
  final name = 'filters';

  @override
  final description = 'Show the saved filters, or remove one. Save one '
      'with `geas find --save`.';

  @override
  String get invocation => 'geas filters\n       geas filters rm <filter>';

  @override
  Future<int> run() async {
    final session = await openSession();
    await session.pull();
    final workspace = session.workspace;
    switch (rest) {
      case []:
        final filters = workspace.filters;
        if (filters.isEmpty) {
          out.writeln('No filters saved yet. Save one with '
              '`geas find --save <name> <query>`.');
          return 0;
        }
        final now = context.clock();
        int width(String Function(SavedFilter f) text) =>
            filters.fold(0, (w, f) => text(f).length > w ? text(f).length : w);
        final idWidth = width((f) => f.id), nameWidth = width((f) => f.name);
        for (final f in filters) {
          final count = TaskQuery.parse(f.query, lists: workspace.lists)
              .search(workspace.tasks, now)
              .length;
          out.writeln('  ${f.id.padRight(idWidth)}  '
              '${f.name.padRight(nameWidth)}  ${'$count'.padLeft(3)}  '
              '${f.query}');
        }
        return 0;
      case ['rm', ...final words] when words.isNotEmpty:
        final filter = resolveFilter(session, words.join(' '));
        await workspace.deleteFilter(filter.id);
        out.writeln('Removed the filter ${filter.name}.');
        await session.push();
        return 0;
      default:
        usageException('Unknown or incomplete `geas filters` command.');
    }
  }
}
