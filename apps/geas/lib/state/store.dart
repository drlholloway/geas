import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';

import 'session.dart';
import 'sync.dart';

/// The current time. Tests override it to pin "today".
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Every task and list the app knows about.
class TaskStore {
  TaskStore({
    required this.tasks,
    required Iterable<TaskList> lists,
    this.loaded = true,
  }) : lists = withInbox(lists);

  /// Before the local copy has been read.
  TaskStore.loading() : this(tasks: const [], lists: const [], loaded: false);

  final List<Task> tasks;

  /// In display order, inbox included.
  final List<TaskList> lists;

  /// False until the local copy has been read.
  final bool loaded;

  TaskList? listById(String id) {
    for (final list in lists) {
      if (list.id == id) return list;
    }
    return null;
  }
}

/// The working copy of the data repo, held in memory. Edits show at once
/// and are written to disk in order; each one asks for a sync soon after.
class TaskStoreNotifier extends Notifier<TaskStore> {
  Workspace? _workspace;

  /// Disk work not yet done, in order.
  Future<void> _queue = Future.value();

  @override
  TaskStore build() {
    final session = ref.watch(sessionProvider);
    if (session == null) return TaskStore(tasks: const [], lists: const []);
    _enqueue(
      () async => _workspace = await Workspace.load(session.store.working),
    );
    return TaskStore.loading();
  }

  DateTime get _now => ref.read(clockProvider)();

  void add(
    String title, {
    String list = inboxId,
    List<String> tags = const [],
    Due? due,
  }) => _save(
    Task.create(title: title, now: _now, list: list, tags: tags, due: due),
  );

  void setDone(Task task, {required bool done}) =>
      _save(done ? task.complete(_now) : task.reopen(_now));

  void setChecklistItem(Task task, int line, {required bool done}) =>
      _save(task.setChecklistItem(line, done: done, now: _now));

  /// Waits for every edit so far to reach disk.
  Future<void> flush() => _queue;

  /// Re-reads the working copy, as after a sync.
  Future<void> reload() => _enqueue(() async => _workspace?.reload());

  void _save(Task task) {
    // Show it now; the disk catches up.
    state = TaskStore(
      tasks: [
        for (final t in state.tasks)
          if (t.id != task.id) t,
        task,
      ],
      lists: state.lists,
    );
    final now = _now;
    _enqueue(() async {
      await _workspace?.saveTask(task, now: now);
      if (ref.mounted) ref.read(syncProvider.notifier).schedule();
    });
  }

  /// Runs [work] after everything queued before it, then shows the
  /// workspace as it stands.
  Future<void> _enqueue(Future<void> Function() work) => _queue = _queue.then((
    _,
  ) async {
    try {
      await work();
    } on Exception catch (e, stack) {
      debugPrint('geas: $e\n$stack');
    }
    // Rebuilt for another repo since: the work still lands in this
    // repo's copy, but the screen shows the new one.
    final workspace = _workspace;
    if (!ref.mounted || workspace == null) return;
    state = TaskStore(tasks: workspace.tasks.toList(), lists: workspace.lists);
  });
}

final taskStoreProvider = NotifierProvider<TaskStoreNotifier, TaskStore>(
  TaskStoreNotifier.new,
);
