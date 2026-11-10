import 'package:geas_core/geas_core.dart';

import 'command.dart';
import 'output.dart';

class MatrixCommand extends GeasCommand {
  MatrixCommand(super.context) {
    argParser
      ..addOption('list', abbr: 'l', help: 'Only this list, by id or name.')
      ..addOption('tag', abbr: 't', help: 'Only tasks with this tag.')
      ..addFlag('undated',
          defaultsTo: true, help: 'Include tasks with no due date.');
  }

  @override
  final name = 'matrix';

  @override
  final description = 'Show open tasks in the Eisenhower matrix: Do (high '
      'priority), Schedule (medium), Delegate (low) and Drop (none).';

  @override
  String get invocation => 'geas matrix [-l <list>] [-t <tag>] [--no-undated]';

  @override
  Future<int> run() async {
    if (rest.isNotEmpty) usageException('matrix takes no arguments.');
    final args = argResults!;
    final session = await openSession();
    await session.pull();
    final now = context.clock();
    final listText = args['list'] as String?;
    final list = listText == null ? null : session.resolveList(listText).id;
    final tag = (args['tag'] as String?)?.replaceFirst(RegExp('^#'), '');
    final matrix = matrixOf(
      session.workspace.tasks,
      now: now,
      list: list,
      tag: tag,
      includeUndated: args['undated'] as bool,
    );

    // One set of columns for every quadrant, so they line up.
    final rows = taskRows(
      [for (final q in Quadrant.values) ...matrix[q]!],
      now: now,
      shortId: session.shortId,
      showList: list == null,
    ).iterator;
    var first = true;
    for (final q in Quadrant.values) {
      if (!first) out.writeln();
      first = false;
      final tasks = matrix[q]!;
      out.writeln('${q.title}: ${q.subtitle.toLowerCase()} '
          '(${q.priority.name} priority)');
      if (tasks.isEmpty) out.writeln('  -');
      for (var i = 0; i < tasks.length; i++) {
        rows.moveNext();
        out.writeln(rows.current);
      }
    }
    return 0;
  }
}
