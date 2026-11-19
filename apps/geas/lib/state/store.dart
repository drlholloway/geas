import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';
import 'package:geas_core/geas_core.dart' as geas show moveTracker;

import 'session.dart';
import 'sync.dart';

/// The current time. Tests override it to pin "today".
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Every task and list the app knows about.
class TaskStore {
  TaskStore({
    required this.tasks,
    required Iterable<TaskList> lists,
    Iterable<Tracker> trackers = const [],
    this.loaded = true,
    this.warnDays = defaultWarnDays,
  }) : lists = withInbox(lists),
       trackers = sortTrackers(trackers);

  /// Before the local copy has been read.
  TaskStore.loading() : this(tasks: const [], lists: const [], loaded: false);

  final List<Task> tasks;

  /// In display order, inbox included.
  final List<TaskList> lists;

  /// What the Health view logs (medications, sensors), in display order.
  final List<Tracker> trackers;

  /// False until the local copy has been read.
  final bool loaded;

  /// Days ahead a due date counts as approaching, from `geas.yaml`.
  final int warnDays;

  TaskStore copyWith({
    List<Task>? tasks,
    Iterable<TaskList>? lists,
    Iterable<Tracker>? trackers,
  }) => TaskStore(
    tasks: tasks ?? this.tasks,
    lists: lists ?? this.lists,
    trackers: trackers ?? this.trackers,
    loaded: loaded,
    warnDays: warnDays,
  );

  Tracker? trackerById(String id) {
    for (final tracker in trackers) {
      if (tracker.id == id) return tracker;
    }
    return null;
  }

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

  /// Adds a new task and returns it.
  Task add(
    String title, {
    String list = inboxId,
    List<String> tags = const [],
    Due? due,
    Order? order,
  }) {
    final task = Task.create(
      title: title,
      now: _now,
      list: list,
      tags: tags,
      due: due,
    ).copyWith(order: order);
    _save(task);
    return task;
  }

  /// Finishes or reopens [task]. Finishing a repeating task also adds the
  /// next one.
  void setDone(Task task, {required bool done}) =>
      _saveAll(done ? completeTask(task, _now) : [task.reopen(_now)]);

  void setChecklistItem(Task task, int line, {required bool done}) =>
      _save(task.setChecklistItem(line, done: done, now: _now));

  /// Applies [change] to the task with [id] as it is now, if it's still
  /// here and [change] changes anything.
  void edit(String id, Task Function(Task task) change) {
    final task = _task(id);
    if (task == null) return;
    final changed = change(task);
    if (changed == task) return;
    _save(changed.copyWith(updated: _now));
  }

  void delete(String id) {
    if (_task(id) == null) return;
    state = state.copyWith(
      tasks: [
        for (final t in state.tasks)
          if (t.id != id) t,
      ],
      lists: state.lists,
    );
    _enqueue(() async {
      await _workspace?.deleteTask(id);
      if (ref.mounted) ref.read(syncProvider.notifier).schedule();
    });
  }

  /// Saves [task] as given, as the current version, keeping its fields
  /// apart from `updated`.
  void restoreTask(Task task) => _save(task.copyWith(updated: _now));

  /// Writes [text] to [path] in the working copy, or deletes the file if
  /// null, then re-reads everything. For files that aren't tasks.
  Future<void> restoreFile(String path, String? text) {
    final session = ref.read(sessionProvider);
    if (session == null) return Future.value();
    return _enqueue(() async {
      final area = session.store.working;
      if (text == null) {
        await area.delete(path);
      } else {
        await area.write(path, utf8.encode(text));
      }
      await _workspace?.reload();
      if (ref.mounted) ref.read(syncProvider.notifier).schedule();
    });
  }

  /// Adds [list], or saves changes to it.
  void saveList(TaskList list) {
    state = state.copyWith(
      tasks: state.tasks,
      lists: [
        for (final l in state.lists)
          if (l.id != list.id) l,
        list,
      ],
    );
    _enqueue(() async {
      await _workspace?.saveList(list);
      if (ref.mounted) ref.read(syncProvider.notifier).schedule();
    });
  }

  /// Removes the list with [id], moving its tasks to the inbox.
  void deleteList(String id) {
    if (id == inboxId) return;
    final now = _now;
    final moved = [
      for (final t in state.tasks)
        if (t.list == id) t.copyWith(list: inboxId, updated: now),
    ];
    state = state.copyWith(
      tasks: _replacing(moved),
      lists: [
        for (final l in state.lists)
          if (l.id != id) l,
      ],
    );
    _enqueue(() async {
      final workspace = _workspace;
      if (workspace == null) return;
      for (final task in moved) {
        await workspace.saveTask(task, now: now);
      }
      await workspace.deleteList(id);
      if (ref.mounted) ref.read(syncProvider.notifier).schedule();
    });
  }

  /// Adds [tracker], or saves changes to it.
  void saveTracker(Tracker tracker) {
    state = state.copyWith(
      trackers: [
        for (final t in state.trackers)
          if (t.id != tracker.id) t,
        tracker,
      ],
    );
    _enqueue(() async {
      await _workspace?.saveTracker(tracker);
      if (ref.mounted) ref.read(syncProvider.notifier).schedule();
    });
  }

  /// Applies [change] to the tracker with [id] as it is now, if it's still
  /// here and [change] changes anything.
  void editTracker(String id, Tracker Function(Tracker tracker) change) {
    final tracker = state.trackerById(id);
    if (tracker == null) return;
    final changed = change(tracker);
    if (changed != tracker) saveTracker(changed);
  }

  /// Moves the tracker with [id] to [index] in the Health view.
  void moveTracker(String id, int index) {
    final changed = geas.moveTracker(state.trackers, id, index);
    if (changed.isEmpty) return;
    final ids = {for (final t in changed) t.id};
    state = state.copyWith(
      trackers: [
        for (final t in state.trackers)
          if (!ids.contains(t.id)) t,
        ...changed,
      ],
    );
    _enqueue(() async {
      for (final tracker in changed) {
        await _workspace?.saveTracker(tracker);
      }
      if (ref.mounted) ref.read(syncProvider.notifier).schedule();
    });
  }

  /// Logs the tracker with [id] at [at], or now, and returns the entry.
  TrackerEntry logTracker(String id, {DateTime? at, String? note}) {
    final time = at ?? _now;
    editTracker(id, (t) => t.log(time, note: note));
    final logged = Tracker(id: id, name: id).log(time, note: note);
    return logged.entries.single;
  }

  /// Removes the tracker with [id] and its log.
  void deleteTracker(String id) {
    state = state.copyWith(
      trackers: [
        for (final t in state.trackers)
          if (t.id != id) t,
      ],
    );
    _enqueue(() async {
      await _workspace?.deleteTracker(id);
      if (ref.mounted) ref.read(syncProvider.notifier).schedule();
    });
  }

  /// Renames [from] to [to] on every task that has it, in any case, or
  /// removes it if [to] is null.
  void renameTag(String from, String? to) {
    final now = _now;
    final lower = from.toLowerCase();
    _saveAll([
      for (final t in state.tasks)
        if (t.tags.any((tag) => tag.toLowerCase() == lower))
          t.copyWith(tags: replaceTag(t.tags, from, to), updated: now),
    ]);
  }

  /// Tasks as they are, with [changed] in place of the ones with their ids
  /// (and added if new).
  List<Task> _replacing(List<Task> changed) {
    final byId = {for (final t in changed) t.id: t};
    return [
      for (final t in state.tasks)
        if (!byId.containsKey(t.id)) t,
      ...changed,
    ];
  }

  Task? _task(String id) {
    for (final task in state.tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  /// Waits for every edit so far to reach disk.
  Future<void> flush() => _queue;

  /// Re-reads the working copy, as after a sync.
  Future<void> reload() => _enqueue(() async => _workspace?.reload());

  void _save(Task task) => _saveAll([task]);

  void _saveAll(List<Task> tasks) {
    if (tasks.isEmpty) return;
    // Show them now; the disk catches up.
    state = state.copyWith(tasks: _replacing(tasks), lists: state.lists);
    final now = _now;
    _enqueue(() async {
      for (final task in tasks) {
        await _workspace?.saveTask(task, now: now);
      }
      if (ref.mounted) ref.read(syncProvider.notifier).schedule();
    });
  }

  /// Runs [work] after everything queued before it, then shows the
  /// workspace as it stands.
  Future<void> _enqueue(Future<void> Function() work) =>
      _queue = _queue.then((_) async {
        try {
          await work();
        } on Exception catch (e, stack) {
          debugPrint('geas: $e\n$stack');
        }
        // Rebuilt for another repo since: the work still lands in this
        // repo's copy, but the screen shows the new one.
        final workspace = _workspace;
        if (!ref.mounted || workspace == null) return;
        state = TaskStore(
          tasks: workspace.tasks.toList(),
          lists: workspace.lists,
          trackers: workspace.trackers,
          warnDays: workspace.warnDays,
        );
      });
}

final taskStoreProvider = NotifierProvider<TaskStoreNotifier, TaskStore>(
  TaskStoreNotifier.new,
);
