import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';

import 'sample_data.dart';

/// The current time. Tests override it to pin "today".
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Every task and list the app knows about.
class TaskStore {
  TaskStore({required this.tasks, required Iterable<TaskList> lists})
    : lists = withInbox(lists);

  final List<Task> tasks;

  /// In display order, inbox included.
  final List<TaskList> lists;

  TaskList? listById(String id) {
    for (final list in lists) {
      if (list.id == id) return list;
    }
    return null;
  }
}

/// Holds the tasks in memory. Until sync lands (Phase 2) it starts from
/// sample data and forgets edits on quit.
class TaskStoreNotifier extends Notifier<TaskStore> {
  @override
  TaskStore build() => sampleStore(ref.read(clockProvider)());

  DateTime get _now => ref.read(clockProvider)();

  void add(
    String title, {
    String list = inboxId,
    List<String> tags = const [],
    Due? due,
  }) {
    final task = Task.create(
      title: title,
      now: _now,
      list: list,
      tags: tags,
      due: due,
    );
    state = TaskStore(tasks: [...state.tasks, task], lists: state.lists);
  }

  void setDone(Task task, {required bool done}) =>
      _replace(done ? task.complete(_now) : task.reopen(_now));

  void setChecklistItem(Task task, int line, {required bool done}) =>
      _replace(task.setChecklistItem(line, done: done, now: _now));

  void _replace(Task task) {
    state = TaskStore(
      tasks: [for (final t in state.tasks) t.id == task.id ? task : t],
      lists: state.lists,
    );
  }
}

final taskStoreProvider = NotifierProvider<TaskStoreNotifier, TaskStore>(
  TaskStoreNotifier.new,
);
