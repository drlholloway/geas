import 'queries.dart';
import 'task.dart';

/// The gap left between neighbors when positions are handed out, so a task
/// can be dropped between two others by changing only its own file.
const positionGap = 1024;

/// [tasks] in a list's hand-set order: by `position`, lowest first. Tasks
/// with none come after those, in the usual order by due date, so a list
/// just switched to sorting by hand starts out looking as it did.
List<Task> manualOrder(Iterable<Task> tasks) => tasks.toList()
  ..sort((a, b) {
    final pa = a.position, pb = b.position;
    if (pa == null || pb == null) {
      if (pa != null) return -1;
      if (pb != null) return 1;
      return compareByDue(a, b);
    }
    final byPosition = pa.compareTo(pb);
    return byPosition != 0 ? byPosition : a.created.compareTo(b.created);
  });

/// The position for a task added to the top of [tasks], a list's open
/// tasks.
int topPosition(Iterable<Task> tasks) {
  final lowest = tasks
      .map((t) => t.position)
      .nonNulls
      .fold<int?>(null, (low, p) => low == null || p < low ? p : low);
  return (lowest ?? positionGap) - positionGap;
}

/// [ordered] (as [manualOrder] gives it) with the task [id] moved to
/// [index]: the tasks whose `position` has to change for that, with
/// `updated` set to [now]. Usually that's the moved task alone, placed
/// halfway between its new neighbors; when there's no room between them,
/// or some have no position yet, every task is renumbered.
List<Task> moveInManualOrder(
  List<Task> ordered,
  String id,
  int index, {
  required DateTime now,
}) {
  final from = ordered.indexWhere((t) => t.id == id);
  if (from < 0) return const [];
  final sequence = [...ordered];
  final moved = sequence.removeAt(from);
  final to = index.clamp(0, sequence.length);
  if (to == from) return const [];
  sequence.insert(to, moved);

  if (sequence.every((t) => t.id == id || t.position != null)) {
    final before = to == 0 ? null : sequence[to - 1].position!;
    final after = to == sequence.length - 1 ? null : sequence[to + 1].position!;
    final int? between = switch ((before, after)) {
      (null, null) => 0,
      (null, final after?) => after - positionGap,
      (final before?, null) => before + positionGap,
      (final before?, final after?) =>
        after - before >= 2 ? before + (after - before) ~/ 2 : null,
    };
    if (between != null) {
      return [moved.copyWith(position: between, updated: now)];
    }
  }
  return [
    for (final (i, task) in sequence.indexed)
      if (task.position != (i + 1) * positionGap)
        task.copyWith(position: (i + 1) * positionGap, updated: now),
  ];
}
