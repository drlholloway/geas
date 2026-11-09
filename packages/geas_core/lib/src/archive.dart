import 'task.dart';

/// How long a completed task stays in `tasks/` before it's archived.
const archiveAfter = Duration(days: 30);

/// Where [task] belongs at [now]: `tasks/<id>.md`, or
/// `archive/<yyyy>/<id>.md` (the year it was completed, UTC) once it has been
/// done for longer than [archiveAfter].
String taskPath(Task task, DateTime now) {
  final completed = task.completed;
  if (completed != null && now.difference(completed) > archiveAfter) {
    return 'archive/${completed.year}/${task.id}.md';
  }
  return 'tasks/${task.id}.md';
}

/// The moves (old path to new path) that put every task in [tasksByPath]
/// where [taskPath] says it belongs. Reopening an archived task moves it
/// back to `tasks/`.
Map<String, String> archiveMoves(Map<String, Task> tasksByPath, DateTime now) =>
    {
      for (final MapEntry(key: path, value: task) in tasksByPath.entries)
        if (taskPath(task, now) != path) path: taskPath(task, now),
    };
