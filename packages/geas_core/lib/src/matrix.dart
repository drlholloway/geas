import 'local_date.dart';
import 'priority.dart';
import 'queries.dart';
import 'task.dart';

/// A quadrant of the Eisenhower matrix. Each is one priority level, as in
/// TickTick; due dates don't move tasks between them.
enum Quadrant {
  /// High priority: urgent and important.
  doFirst('Do', 'Urgent and important', Priority.high),

  /// Medium priority: important, not urgent.
  schedule('Schedule', 'Important, not urgent', Priority.medium),

  /// Low priority: urgent, not important.
  delegate('Delegate', 'Urgent, not important', Priority.low),

  /// No priority: neither.
  drop('Drop', 'Neither', Priority.none);

  const Quadrant(this.title, this.subtitle, this.priority);

  final String title;
  final String subtitle;

  /// The priority every task in this quadrant has. Moving a task here sets
  /// it.
  final Priority priority;

  static Quadrant of(Priority priority) =>
      values.firstWhere((q) => q.priority == priority);
}

/// How close an open task is to its due date.
enum DueWarning { none, approaching, overdue }

/// Days ahead a due date counts as approaching unless `geas.yaml` sets
/// `warn_days`.
const defaultWarnDays = 2;

/// [task]'s warning at [now]: overdue past its due date or time,
/// approaching when due within [warnDays] days (today counts), otherwise
/// none. Completed and undated tasks have none.
DueWarning dueWarning(
  Task task,
  DateTime now, {
  int warnDays = defaultWarnDays,
}) {
  final due = task.due;
  if (task.isCompleted || due == null) return DueWarning.none;
  if (dueBucket(task, now) == DueBucket.overdue) return DueWarning.overdue;
  final last = LocalDate.of(now.toLocal()).addDays(warnDays);
  return due.localDate.isAfter(last) ? DueWarning.none : DueWarning.approaching;
}

/// Open [tasks] in each quadrant, in the default order, optionally only
/// those in [list] or tagged [tag], and without undated tasks unless
/// [includeUndated].
Map<Quadrant, List<Task>> matrixOf(
  Iterable<Task> tasks, {
  required DateTime now,
  String? list,
  String? tag,
  bool includeUndated = true,
}) {
  final matrix = {for (final q in Quadrant.values) q: <Task>[]};
  for (final task in openTasks(tasks, now: now, list: list, tag: tag)) {
    if (!includeUndated && task.due == null) continue;
    matrix[Quadrant.of(task.priority)]!.add(task);
  }
  return matrix;
}
