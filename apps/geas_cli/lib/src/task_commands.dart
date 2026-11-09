import 'dart:io';

import 'package:geas_core/geas_core.dart';
import 'package:path/path.dart' as p;

import 'command.dart';
import 'context.dart';
import 'output.dart';

const _priorityShorthands = {
  'h': 'high',
  'm': 'medium',
  'med': 'medium',
  'l': 'low',
  'n': 'none',
};

Priority _parsePriority(String text) =>
    Priority.parse(_priorityShorthands[text.trim().toLowerCase()] ?? text);

String _stripHash(String tag) => tag.startsWith('#') ? tag.substring(1) : tag;

class AddCommand extends GeasCommand {
  AddCommand(super.context) {
    argParser
      ..addOption('list', abbr: 'l', help: 'The list, by id or name.')
      ..addMultiOption('tag',
          abbr: 't',
          help: 'A tag; repeat or separate '
              'with commas for more.')
      ..addOption('due',
          abbr: 'd',
          help: 'today, tomorrow, a weekday or '
              'YYYY-MM-DD, optionally with a time: "fri 17:00", "tomorrow 5pm".')
      ..addOption('priority',
          abbr: 'p',
          help: 'high, medium, low or none '
              '(h, m, l, n).');
  }

  @override
  final name = 'add';

  @override
  final description = 'Add a task.';

  @override
  String get invocation => 'geas add "<title>" [-l <list>] [-t <tag>]... '
      '[-d <due>] [-p <priority>]';

  @override
  Future<int> run() async {
    final title = rest.join(' ').trim();
    if (title.isEmpty) usageException('Give the task a title.');
    final now = context.clock();
    final args = argResults!;
    final dueText = args['due'] as String?;
    final priorityText = args['priority'] as String?;
    final Due? due;
    final Priority priority;
    try {
      due = dueText == null ? null : parseDueInput(dueText, now: now);
      priority =
          priorityText == null ? Priority.none : _parsePriority(priorityText);
    } on FormatException catch (e) {
      usageException(e.message);
    }

    final session = await openSession();
    await session.pull();
    final listText = args['list'] as String?;
    final list = listText == null ? inboxId : session.resolveList(listText).id;
    final task = await session.workspace.saveTask(
      Task.create(
        title: title,
        now: now,
        list: list,
        tags: [
          for (final tag in args['tag'] as List<String>)
            if (_stripHash(tag.trim()).isNotEmpty) _stripHash(tag.trim()),
        ],
        due: due,
        priority: priority,
      ),
      now: now,
    );
    await session.reload();
    final when = due == null ? '' : ', due ${dueLabel(due, now)}';
    out.writeln('Added ${session.shortId(task.id)} ${task.title}$when.');
    await session.push();
    return 0;
  }
}

class LsCommand extends GeasCommand {
  LsCommand(super.context) {
    argParser
      ..addOption('list', abbr: 'l', help: 'Only this list, by id or name.')
      ..addOption('tag', abbr: 't', help: 'Only tasks with this tag.')
      ..addFlag('today', negatable: false, help: 'Overdue and due today.')
      ..addFlag('overdue', negatable: false, help: 'Only overdue.')
      ..addFlag('week',
          negatable: false, help: 'Overdue and due in the next 7 days.')
      ..addFlag('done',
          negatable: false, help: 'Completed tasks, most recent first.');
  }

  @override
  final name = 'ls';

  @override
  final description = 'List open tasks, grouped by when they\'re due.';

  @override
  String get invocation => 'geas ls [-l <list>] [-t <tag>] '
      '[--today | --overdue | --week] [--done]';

  @override
  Future<int> run() async {
    if (rest.isNotEmpty) usageException('ls takes no arguments.');
    final args = argResults!;
    final windows = ['today', 'overdue', 'week'].where((w) => args[w] as bool);
    if (windows.length > 1) {
      usageException('Use one of --today, --overdue and --week.');
    }
    final window = windows.firstOrNull;
    if (window != null && args['done'] as bool) {
      usageException('--$window is for open tasks; drop it or --done.');
    }

    final session = await openSession();
    await session.pull();
    final workspace = session.workspace;
    final now = context.clock();
    final listText = args['list'] as String?;
    final list = listText == null ? null : session.resolveList(listText).id;
    final tagText = args['tag'] as String?;
    final tag = tagText == null ? null : _stripHash(tagText);

    if (args['done'] as bool) {
      final done = completedTasks(workspace.tasks, list: list, tag: tag);
      if (done.isEmpty) {
        out.writeln('No completed tasks.');
      } else {
        out.writeln('Completed');
        taskRows(
          done,
          now: now,
          shortId: session.shortId,
          showList: list == null,
          when: (t) => 'done ${LocalDate.of(t.completed!.toLocal())}',
        ).forEach(out.writeln);
      }
      return 0;
    }

    final today = LocalDate.of(now.toLocal());
    bool shown(Task task, DueBucket bucket) => switch (window) {
          null => true,
          'overdue' => bucket == DueBucket.overdue,
          'today' => bucket == DueBucket.overdue || bucket == DueBucket.today,
          _ => bucket == DueBucket.overdue ||
              bucket == DueBucket.today ||
              bucket == DueBucket.upcoming &&
                  task.due!.localDate.isBefore(today.addDays(7)),
        };
    final groups = <DueBucket, List<Task>>{};
    for (final task
        in openTasks(workspace.tasks, now: now, list: list, tag: tag)) {
      final bucket = dueBucket(task, now);
      if (shown(task, bucket)) (groups[bucket] ??= []).add(task);
    }
    if (groups.isEmpty) {
      out.writeln('Nothing to do.');
    } else {
      // One set of columns for every group, so they line up.
      final rows = taskRows(
        [for (final bucket in DueBucket.values) ...?groups[bucket]],
        now: now,
        shortId: session.shortId,
        showList: list == null,
      ).iterator;
      var first = true;
      for (final bucket in DueBucket.values) {
        final tasks = groups[bucket];
        if (tasks == null) continue;
        if (!first) out.writeln();
        first = false;
        out.writeln(_headings[bucket]);
        for (var i = 0; i < tasks.length; i++) {
          rows.moveNext();
          out.writeln(rows.current);
        }
      }
    }
    _reportProblems(workspace);
    return 0;
  }

  static const _headings = {
    DueBucket.overdue: 'Overdue',
    DueBucket.today: 'Today',
    DueBucket.upcoming: 'Upcoming',
    DueBucket.noDate: 'No date',
  };

  void _reportProblems(Workspace workspace) {
    workspace.problems.forEach((path, problem) {
      warn('Skipped $path: $problem');
    });
  }
}

class ShowCommand extends GeasCommand {
  ShowCommand(super.context);

  @override
  final name = 'show';

  @override
  final description = 'Show a task in full.';

  @override
  String get invocation => 'geas show <id>';

  @override
  Future<int> run() async {
    if (rest.length != 1) usageException('Give one task id.');
    final session = await openSession();
    await session.pull();
    final task = session.resolveTask(rest.single);
    final now = context.clock();
    final list = session.workspace.lists
        .where((l) => l.id == task.list)
        .map((l) => l.name)
        .firstOrNull;
    final due = task.due;
    final fields = {
      'id': '${task.id} (${session.shortId(task.id)})',
      'list': list ?? '${task.list} (no such list)',
      if (task.tags.isNotEmpty) 'tags': task.tags.map((t) => '#$t').join(' '),
      if (due != null)
        'due': [
          formatDate(due.localDate),
          if (due.hasTime) dueTime(due),
          '(${dueLabel(due, now)})',
        ].join(' '),
      if (task.priority != Priority.none) 'priority': task.priority.name,
      'created': formatTime(task.created),
      'updated': formatTime(task.updated),
      if (task.completed != null) 'done': formatTime(task.completed!),
    };
    out.writeln(task.title);
    fields.forEach((key, value) => out.writeln('  ${key.padRight(8)}  $value'));
    final body = task.body.trim();
    if (body.isNotEmpty) out.writeln('\n$body');
    return 0;
  }
}

class DoneCommand extends GeasCommand {
  DoneCommand(super.context) {
    argParser.addFlag('undo',
        abbr: 'u', negatable: false, help: 'Mark open again.');
  }

  @override
  final name = 'done';

  @override
  final description = 'Mark tasks done, or open again with --undo.';

  @override
  String get invocation => 'geas done <id>... [--undo]';

  @override
  Future<int> run() async {
    if (rest.isEmpty) usageException('Give at least one task id.');
    final undo = argResults!['undo'] as bool;
    final session = await openSession();
    await session.pull();
    final tasks = [for (final id in rest) session.resolveTask(id)];
    final now = context.clock();
    var changed = false;
    for (final task in tasks) {
      final label = '${session.shortId(task.id)} ${task.title}';
      if (task.isCompleted != undo) {
        out.writeln(
            undo ? '$label is already open.' : '$label is already done.');
        continue;
      }
      await session.workspace
          .saveTask(undo ? task.reopen(now) : task.complete(now), now: now);
      out.writeln('${undo ? 'Reopened' : 'Done:'} $label');
      changed = true;
    }
    if (changed) await session.push();
    return 0;
  }
}

class RmCommand extends GeasCommand {
  RmCommand(super.context);

  @override
  final name = 'rm';

  @override
  final description = 'Delete tasks. Git history keeps them.';

  @override
  String get invocation => 'geas rm <id>...';

  @override
  Future<int> run() async {
    if (rest.isEmpty) usageException('Give at least one task id.');
    final session = await openSession();
    await session.pull();
    final tasks = [for (final id in rest) session.resolveTask(id)];
    for (final task in tasks) {
      final label = '${session.shortId(task.id)} ${task.title}';
      await session.workspace.deleteTask(task.id);
      out.writeln('Removed $label');
    }
    await session.push();
    return 0;
  }
}

class EditCommand extends GeasCommand {
  EditCommand(super.context);

  @override
  final name = 'edit';

  @override
  final description =
      'Edit a task file in \$VISUAL or \$EDITOR. It is checked when you '
      'save; the id can\'t change.';

  @override
  String get invocation => 'geas edit <id>';

  @override
  Future<int> run() async {
    if (rest.length != 1) usageException('Give one task id.');
    final session = await openSession();
    await session.pull();
    final task = session.resolveTask(rest.single);
    final label = session.shortId(task.id);
    final original = task.encode();

    final dir = await Directory.systemTemp.createTemp('geas-edit-');
    final file = File(p.join(dir.path, '${task.id}.md'));
    await file.writeAsString(original);
    var keep = false;
    try {
      while (true) {
        if (!await context.editFile(file.path)) {
          throw const CliException('The editor failed. Nothing changed.');
        }
        final text = await file.readAsString();
        if (text == original) {
          out.writeln('No changes.');
          return 0;
        }
        try {
          final edited = Task.parse(text);
          if (edited.id != task.id) {
            throw FormatException('The id has to stay ${task.id}.');
          }
          final now = context.clock();
          final saved = await session.workspace
              .saveTask(edited.copyWith(updated: now), now: now);
          if (!session.workspace.lists.any((l) => l.id == saved.list)) {
            warn('There is no list "${saved.list}" yet.');
          }
          out.writeln('Saved $label ${saved.title}');
          await session.push();
          return 0;
        } on FormatException catch (e) {
          context.err.writeln('geas: ${e.message}');
          if (!context.confirm('Edit again?')) {
            keep = true;
            throw CliException(
                'Nothing changed. Your edit is in ${file.path}.');
          }
        }
      }
    } finally {
      if (!keep) await dir.delete(recursive: true);
    }
  }
}
