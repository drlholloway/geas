import 'package:geas_core/geas_core.dart';

import '../../state/store.dart';
import 'due_label.dart';

enum ViewKind { list, today, week, tag }

/// A titled group of tasks on screen.
class TaskSection {
  const TaskSection(this.title, this.tasks, {this.alert = false});

  final String title;
  final List<Task> tasks;

  /// Drawn in the error color (overdue).
  final bool alert;
}

/// What the task screen is showing: one list, Today, Next 7 days or a tag.
class TaskView {
  const TaskView(this.kind, [this.arg = '']);

  final ViewKind kind;

  /// The list id or tag; empty for Today and Next 7 days.
  final String arg;

  String get location => switch (kind) {
    ViewKind.list => '/list/${Uri.encodeComponent(arg)}',
    ViewKind.today => '/today',
    ViewKind.week => '/week',
    ViewKind.tag => '/tag/${Uri.encodeComponent(arg)}',
  };

  String title(TaskStore store) => switch (kind) {
    ViewKind.list => store.listById(arg)?.name ?? arg,
    ViewKind.today => 'Today',
    ViewKind.week => 'Next 7 days',
    ViewKind.tag => '#$arg',
  };

  /// The list new tasks from the quick-add field go to.
  String get newTaskList => kind == ViewKind.list ? arg : inboxId;

  List<String> get newTaskTags => kind == ViewKind.tag ? [arg] : const [];

  /// Today's view files new tasks under today.
  Due? newTaskDue(DateTime now) =>
      kind == ViewKind.today ? Due.date(LocalDate.of(now)) : null;

  List<TaskSection> sections(TaskStore store, DateTime now) {
    final list = kind == ViewKind.list ? arg : null;
    final tag = kind == ViewKind.tag ? arg : null;
    final overdue = TaskSection(
      'Overdue',
      openTasks(
        store.tasks,
        now: now,
        list: list,
        tag: tag,
        window: DueWindow.overdue,
      ),
      alert: true,
    );
    final List<TaskSection> rest;
    switch (kind) {
      case ViewKind.list || ViewKind.tag:
        final open = openTasks(store.tasks, now: now, list: list, tag: tag);
        List<Task> inBucket(DueBucket b) => [
          for (final t in open)
            if (dueBucket(t, now) == b) t,
        ];
        rest = [
          TaskSection('Today', inBucket(DueBucket.today)),
          TaskSection('Upcoming', inBucket(DueBucket.upcoming)),
          TaskSection('No date', inBucket(DueBucket.noDate)),
        ];
      case ViewKind.today:
        final arriving = <Task>{
          for (final s in packagesArriving(store.tasks, now: now)) s.task,
        };
        rest = [
          TaskSection(
            'Today',
            openTasks(store.tasks, now: now, window: DueWindow.today),
          ),
          TaskSection('Packages arriving', arriving.toList()),
        ];
      case ViewKind.week:
        // One section per day.
        final byDay = <LocalDate, List<Task>>{};
        for (final t in openTasks(
          store.tasks,
          now: now,
          window: DueWindow.next7Days,
        )) {
          byDay.putIfAbsent(t.due!.localDate, () => []).add(t);
        }
        rest = [
          for (final MapEntry(key: day, value: tasks) in byDay.entries)
            TaskSection(dayLabel(day, now), tasks),
        ];
    }
    return [overdue, ...rest].where((s) => s.tasks.isNotEmpty).toList();
  }

  /// Done tasks for the collapsed Completed section.
  List<Task> completed(TaskStore store) => switch (kind) {
    ViewKind.list => completedTasks(store.tasks, list: arg),
    ViewKind.tag => completedTasks(store.tasks, tag: arg),
    ViewKind.today || ViewKind.week => const [],
  };

  /// Open tasks counted next to this view in the sidebar.
  int openCount(TaskStore store, DateTime now) => {
    for (final s in sections(store, now))
      for (final t in s.tasks) t.id,
  }.length;
}
