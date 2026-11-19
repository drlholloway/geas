import 'dart:convert';

import '../archive.dart';
import '../filter.dart';
import '../matrix.dart';
import '../repo_config.dart';
import '../task.dart';
import '../task_list.dart';
import '../tracker.dart';
import 'file_area.dart';

/// The tasks, lists and trackers in a device's working copy, indexed in memory. The
/// app and CLI read and edit through this; sync works on the files.
class Workspace {
  Workspace._(this._area);

  /// Loads every task and list in [area]. Files that don't parse are left
  /// alone and reported in [problems].
  static Future<Workspace> load(FileArea area) async {
    final workspace = Workspace._(area);
    workspace._index(await area.readAll());
    return workspace;
  }

  final FileArea _area;
  final _tasks = <String, Task>{};
  final _taskPaths = <String, String>{};
  final _lists = <String, TaskList>{};
  final _trackers = <String, Tracker>{};
  final _filters = <String, SavedFilter>{};
  final _problems = <String, String>{};
  RepoConfig? _config;

  Iterable<Task> get tasks => _tasks.values;

  /// In display order, inbox included.
  List<TaskList> get lists => withInbox(_lists.values);

  /// In display order.
  List<Tracker> get trackers => sortTrackers(_trackers.values);

  Tracker? tracker(String id) => _trackers[id];

  /// Saved searches, in display order.
  List<SavedFilter> get filters => sortFilters(_filters.values);

  /// Files that couldn't be read, by path, with the reason.
  Map<String, String> get problems => Map.unmodifiable(_problems);

  /// `geas.yaml`, or null if it's missing or doesn't parse.
  RepoConfig? get config => _config;

  /// Days ahead a due date counts as approaching.
  int get warnDays => _config?.warnDays ?? defaultWarnDays;

  Task? task(String id) => _tasks[id];

  /// Re-reads everything, as after a sync.
  Future<void> reload() async {
    _tasks.clear();
    _taskPaths.clear();
    _lists.clear();
    _trackers.clear();
    _filters.clear();
    _problems.clear();
    _config = null;
    _index(await _area.readAll());
  }

  /// Writes [task] where it belongs at [now], moving it if that changed,
  /// and returns it as re-read from disk.
  Future<Task> saveTask(Task task, {required DateTime now}) async {
    final path = taskPath(task, now);
    final text = task.encode();
    await _area.write(path, utf8.encode(text));
    final old = _taskPaths[task.id];
    if (old != null && old != path) await _area.delete(old);
    final saved = Task.parse(text);
    _tasks[task.id] = saved;
    _taskPaths[task.id] = path;
    return saved;
  }

  Future<void> deleteTask(String id) async {
    final path = _taskPaths.remove(id);
    _tasks.remove(id);
    if (path != null) await _area.delete(path);
  }

  Future<TaskList> saveList(TaskList list) async {
    final text = list.encode();
    await _area.write(_listPath(list.id), utf8.encode(text));
    return _lists[list.id] = TaskList.parse(text);
  }

  /// Removes the list file. Its tasks keep their `list` until moved; the
  /// built-in inbox can't be removed, only reset.
  Future<void> deleteList(String id) async {
    _lists.remove(id);
    await _area.delete(_listPath(id));
  }

  Future<Tracker> saveTracker(Tracker tracker) async {
    final text = tracker.encode();
    await _area.write(trackerPath(tracker.id), utf8.encode(text));
    return _trackers[tracker.id] = Tracker.parse(text);
  }

  Future<SavedFilter> saveFilter(SavedFilter filter) async {
    final text = filter.encode();
    await _area.write(filterPath(filter.id), utf8.encode(text));
    return _filters[filter.id] = SavedFilter.parse(text);
  }

  Future<void> deleteFilter(String id) async {
    _filters.remove(id);
    await _area.delete(filterPath(id));
  }

  /// Removes the tracker and its log.
  Future<void> deleteTracker(String id) async {
    _trackers.remove(id);
    await _area.delete(trackerPath(id));
  }

  static String _listPath(String id) => 'lists/$id.yaml';

  void _index(Map<String, List<int>> files) {
    files.forEach((path, bytes) {
      if (path == repoConfigPath) {
        try {
          _config = RepoConfig.parse(utf8.decode(bytes));
        } on FormatException catch (e) {
          _problems[path] = e.message;
        }
        return;
      }
      final isTask =
          (path.startsWith('tasks/') || path.startsWith('archive/')) &&
              path.endsWith('.md');
      final isList = path.startsWith('lists/') && path.endsWith('.yaml');
      final isTracker = isTrackerPath(path);
      final isFilter = isFilterPath(path);
      if (!isTask && !isList && !isTracker && !isFilter) return;
      try {
        final text = utf8.decode(bytes);
        if (isFilter) {
          final filter = SavedFilter.parse(text);
          _filters[filter.id] = filter;
        } else if (isTracker) {
          final tracker = Tracker.parse(text);
          _trackers[tracker.id] = tracker;
        } else if (isTask) {
          final task = Task.parse(text);
          final other = _taskPaths[task.id];
          if (other != null) {
            _problems[path] = 'Same id as $other.';
            return;
          }
          _tasks[task.id] = task;
          _taskPaths[task.id] = path;
        } else {
          final list = TaskList.parse(text);
          _lists[list.id] = list;
        }
      } on FormatException catch (e) {
        _problems[path] = e.message;
      }
    });
  }
}
