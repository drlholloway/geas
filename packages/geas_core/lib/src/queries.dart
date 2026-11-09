import 'local_date.dart';
import 'task.dart';

/// Where an open task sits relative to now.
enum DueBucket { overdue, today, upcoming, noDate }

/// A due-date filter for [openTasks]. None of them include overdue tasks,
/// which have their own window.
enum DueWindow { overdue, today, next7Days }

/// Which [DueBucket] [task] is in at [now]. A timed task is overdue once its
/// time passes; a date-only task once its day is over.
DueBucket dueBucket(Task task, DateTime now) {
  final due = task.due;
  if (due == null) return DueBucket.noDate;
  final today = LocalDate.of(now.toLocal());
  final instant = due.instant;
  final overdue =
      instant != null ? instant.isBefore(now) : due.date.isBefore(today);
  if (overdue) return DueBucket.overdue;
  return due.localDate == today ? DueBucket.today : DueBucket.upcoming;
}

/// Open tasks matching every filter given, in [compareByDue] order.
List<Task> openTasks(
  Iterable<Task> tasks, {
  required DateTime now,
  String? list,
  String? tag,
  DueWindow? window,
}) {
  final today = LocalDate.of(now.toLocal());
  bool inWindow(Task task) {
    if (window == null) return true;
    final bucket = dueBucket(task, now);
    return switch (window) {
      DueWindow.overdue => bucket == DueBucket.overdue,
      DueWindow.today => bucket == DueBucket.today,
      DueWindow.next7Days =>
        (bucket == DueBucket.today || bucket == DueBucket.upcoming) &&
            task.due!.localDate.isBefore(today.addDays(7)),
    };
  }

  return tasks
      .where((t) => !t.isCompleted && _matches(t, list, tag) && inWindow(t))
      .toList()
    ..sort(compareByDue);
}

/// Completed tasks matching every filter given, most recently done first.
List<Task> completedTasks(Iterable<Task> tasks, {String? list, String? tag}) =>
    tasks.where((t) => t.isCompleted && _matches(t, list, tag)).toList()
      ..sort((a, b) {
        final byDone = b.completed!.compareTo(a.completed!);
        return byDone != 0 ? byDone : a.id.compareTo(b.id);
      });

/// Every tag in use, sorted, deduplicated without regard to case (the first
/// spelling seen wins).
List<String> allTags(Iterable<Task> tasks) {
  final byLower = <String, String>{};
  for (final task in tasks) {
    for (final tag in task.tags) {
      byLower.putIfAbsent(tag.toLowerCase(), () => tag);
    }
  }
  return byLower.values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

/// The default order: by due date (all-day before timed on the same day, no
/// date last), then priority, highest first, then oldest first.
int compareByDue(Task a, Task b) {
  final da = a.due, db = b.due;
  if (da == null || db == null) {
    if (da != db) return da == null ? 1 : -1;
  } else {
    final byDate = da.localDate.compareTo(db.localDate);
    if (byDate != 0) return byDate;
    final ia = da.instant, ib = db.instant;
    if (ia == null || ib == null) {
      if (ia != ib) return ia == null ? -1 : 1;
    } else {
      final byTime = ia.compareTo(ib);
      if (byTime != 0) return byTime;
    }
  }
  final byPriority = b.priority.index.compareTo(a.priority.index);
  if (byPriority != 0) return byPriority;
  final byCreated = a.created.compareTo(b.created);
  return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
}

bool _matches(Task task, String? list, String? tag) {
  if (list != null && task.list != list) return false;
  if (tag == null) return true;
  final lower = tag.toLowerCase();
  return task.tags.any((t) => t.toLowerCase() == lower);
}
