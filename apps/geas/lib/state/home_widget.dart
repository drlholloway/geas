import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';

import 'package:geas_core/geas_core.dart';
import 'package:home_widget/home_widget.dart';

import 'environment.dart';
import 'reminders.dart';
import 'sync_lock.dart';

/// The Android home-screen widget that shows the Eisenhower matrix. The app
/// hands it a snapshot of the matrix ([matrixSnapshot]) whenever the tasks
/// change; the widget draws it natively, working out due-date warnings
/// itself so they stay right on days the app isn't opened.
///
/// Taps come back as links: `geas://matrix` opens the Matrix,
/// `geas://task/<id>` opens a task, and `geas://done/<id>`, from a
/// checkbox, finishes one in the background ([homeWidgetCallback]).
abstract interface class HomeWidgetHost {
  /// Gives the widget [snapshot], a JSON [matrixSnapshot], and redraws it.
  Future<void> show(String snapshot);

  /// Gives the Health widget [snapshot], a JSON [healthSnapshot], and
  /// redraws it.
  Future<void> showHealth(String snapshot);

  /// The link that launched the app, if a widget tap did.
  Future<Uri?> launchedFrom();

  /// Links from widget taps while the app is running.
  Stream<Uri> get clicks;
}

/// The real widget, through the home_widget plugin.
class AndroidHomeWidget implements HomeWidgetHost {
  static const _receiver = 'dev.laneholloway.geas.MatrixWidgetReceiver';
  static const _healthReceiver = 'dev.laneholloway.geas.HealthWidgetReceiver';

  @override
  Future<void> show(String snapshot) async {
    await HomeWidget.saveWidgetData<String>(snapshotKey, snapshot);
    await HomeWidget.updateWidget(qualifiedAndroidName: _receiver);
  }

  @override
  Future<void> showHealth(String snapshot) async {
    await HomeWidget.saveWidgetData<String>(healthSnapshotKey, snapshot);
    await HomeWidget.updateWidget(qualifiedAndroidName: _healthReceiver);
  }

  @override
  Future<Uri?> launchedFrom() => HomeWidget.initiallyLaunchedFromHomeWidget();

  @override
  Stream<Uri> get clicks =>
      HomeWidget.widgetClicked.where((uri) => uri != null).cast<Uri>();
}

/// Where the snapshots are kept for the widgets.
const snapshotKey = 'matrix';
const healthSnapshotKey = 'health';

/// Most tasks a quadrant sends; the widget scrolls through these and shows
/// the full count.
const snapshotTasksPerQuadrant = 30;

/// The open [tasks] in the four quadrants, for the widget to draw. Each
/// task has its id, title, and due day (`day`, local) and instant (`at`,
/// milliseconds since the epoch) if it has them.
Map<String, Object?> matrixSnapshot(
  Iterable<Task> tasks, {
  required DateTime now,
  required int warnDays,
}) {
  final matrix = matrixOf(tasks, now: now);
  return {
    'version': 1,
    'warn_days': warnDays,
    'quadrants': [
      for (final q in Quadrant.values)
        {
          'key': q.name,
          'title': q.title,
          'priority': q.priority.name,
          'count': matrix[q]!.length,
          'tasks': [
            for (final task in matrix[q]!.take(snapshotTasksPerQuadrant))
              {
                'id': task.id,
                'title': task.title,
                if (task.due case final due?) ...{
                  'day': '${due.localDate}',
                  if (due.instant case final at?)
                    'at': at.millisecondsSinceEpoch,
                },
              },
          ],
        },
    ],
  };
}

/// Sends the matrix in [workspace] to the widget, if there is one.
Future<void> showMatrix(
  HomeWidgetHost? host,
  Iterable<Task> tasks, {
  required DateTime now,
  required int warnDays,
}) async {
  if (host == null) return;
  await host.show(
    jsonEncode(matrixSnapshot(tasks, now: now, warnDays: warnDays)),
  );
}

/// The [trackers] for the Health widget to draw: each one's name, the words
/// for logging it, and when it was last logged (`last`) and is next due
/// (`due`), in milliseconds since the epoch, if it has them. The widget
/// works out what's overdue itself.
Map<String, Object?> healthSnapshot(
  Iterable<Tracker> trackers, {
  required DateTime now,
}) => {
  'version': 1,
  'trackers': [
    for (final tracker in trackers)
      () {
        final stats = TrackerStats.of(tracker, now);
        return {
          'id': tracker.id,
          'name': tracker.name,
          'action': tracker.kind.action,
          'done': tracker.kind.done,
          if (stats.last case final last?) 'last': last.millisecondsSinceEpoch,
          if (stats.nextDue case final due?) 'due': due.millisecondsSinceEpoch,
        };
      }(),
  ],
};

/// Sends [trackers] to the Health widget, if there is one.
Future<void> showHealth(
  HomeWidgetHost? host,
  Iterable<Tracker> trackers, {
  required DateTime now,
}) async {
  if (host == null) return;
  await host.showHealth(jsonEncode(healthSnapshot(trackers, now: now)));
}

/// The id in a `geas://log/<id>` link, else null.
String? logTrackerId(Uri? uri) =>
    uri != null &&
        uri.scheme == 'geas' &&
        uri.host == 'log' &&
        uri.pathSegments.length == 1
    ? uri.pathSegments.single
    : null;

/// The id in a `geas://done/<id>` link, else null.
String? doneTaskId(Uri? uri) =>
    uri != null &&
        uri.scheme == 'geas' &&
        uri.host == 'done' &&
        uri.pathSegments.length == 1
    ? uri.pathSegments.single
    : null;

/// The name the running app listens under for tasks ticked off on the
/// widget, as `[id, SendPort reply]`, and trackers logged on it, as
/// `['log', id, SendPort reply]`; it replies true once it has them.
const donePortName = 'geas.widget.done';

/// Runs in a background isolate when a widget checkbox or a Health
/// widget's button is tapped.
@pragma('vm:entry-point')
Future<void> homeWidgetCallback(Uri? uri) async {
  final tracker = logTrackerId(uri);
  if (tracker != null) {
    if (await handToApp(tracker, log: true)) return;
    return logFromWidget(tracker, await AppEnvironment.platform());
  }
  final id = doneTaskId(uri);
  if (id == null) return;
  // The app is open: let it finish the task, so its copy stays current
  // and two syncs don't run on the same files.
  if (await handToApp(id)) return;
  await completeFromWidget(id, await AppEnvironment.platform());
}

/// Passes [id] to the running app, if it's listening, and waits for it to
/// take it: a task to finish, or with [log] a tracker to log now. False if
/// there's no app or it didn't answer.
Future<bool> handToApp(
  String id, {
  bool log = false,
  Duration wait = const Duration(seconds: 2),
}) async {
  final app = IsolateNameServer.lookupPortByName(donePortName);
  if (app == null) return false;
  final reply = ReceivePort();
  try {
    app.send(log ? ['log', id, reply.sendPort] : [id, reply.sendPort]);
    return await reply.first.timeout(wait) == true;
  } on TimeoutException {
    // Registered by an app that has since closed.
    return false;
  } finally {
    reply.close();
  }
}

/// Finishes the task with [id] in this device's copy, redraws the widget,
/// then syncs. Offline, the change goes out with the next sync.
Future<void> completeFromWidget(
  String id,
  AppEnvironment env, {
  DateTime Function() clock = DateTime.now,
}) async {
  final config = await env.config.load();
  if (config == null) return;
  final store = env.openStore(config.repo);
  final workspace = await Workspace.load(store.working);
  final token = await env.tokens.read(config.repo);

  /// Syncs and re-reads the copy; false if the sync failed.
  Future<bool> sync() async {
    if (token == null || token.isEmpty) return false;
    try {
      // Waits out a background sync that's running.
      await withSyncLock(
        Syncer(
          github: env.connect(config.repo, token),
          store: store,
          device: config.device,
          clock: clock,
        ).sync,
      );
    } on Exception {
      return false;
    }
    await workspace.reload();
    return true;
  }

  /// Finishes the task if it's here and open; true if it did.
  Future<bool> finish() async {
    final task = workspace.task(id);
    if (task == null || task.isCompleted) return false;
    final now = clock();
    // A repeating task also gets its next one.
    for (final saved in completeTask(task, now)) {
      await workspace.saveTask(saved, now: now);
    }
    return true;
  }

  Future<void> redraw() => showMatrix(
    env.homeWidget,
    workspace.tasks,
    now: clock(),
    warnDays: workspace.warnDays,
  );

  // Not in this copy, as when the app's data was cleared: fetch it first.
  if (workspace.task(id) == null && !await sync()) return;
  final finished = await finish();
  await redraw();
  // A finished task's reminder goes; a repeating one's next is set.
  if (finished) {
    await scheduleReminders(
      env.reminders,
      on: config.reminders,
      tasks: workspace.tasks,
      trackers: workspace.trackers,
      now: clock(),
    );
  }
  // Offline, the change goes out with the next sync.
  if (finished && await sync()) await redraw();
}

/// Logs the tracker with [id] now in this device's copy, redraws the Health
/// widget, then syncs. Offline, the change goes out with the next sync.
Future<void> logFromWidget(
  String id,
  AppEnvironment env, {
  DateTime Function() clock = DateTime.now,
}) async {
  final config = await env.config.load();
  if (config == null) return;
  final store = env.openStore(config.repo);
  final workspace = await Workspace.load(store.working);
  final token = await env.tokens.read(config.repo);

  /// Syncs and re-reads the copy; false if the sync failed.
  Future<bool> sync() async {
    if (token == null || token.isEmpty) return false;
    try {
      await withSyncLock(
        Syncer(
          github: env.connect(config.repo, token),
          store: store,
          device: config.device,
          clock: clock,
        ).sync,
      );
    } on Exception {
      return false;
    }
    await workspace.reload();
    return true;
  }

  Future<void> redraw() =>
      showHealth(env.homeWidget, workspace.trackers, now: clock());

  // Not in this copy, as when the app's data was cleared: fetch it first.
  if (workspace.tracker(id) == null && !await sync()) return;
  final tracker = workspace.tracker(id);
  if (tracker != null) await workspace.saveTracker(tracker.log(clock()));
  await redraw();
  if (tracker == null) return;
  // Its next reminder counts from this log.
  await scheduleReminders(
    env.reminders,
    on: config.reminders,
    tasks: workspace.tasks,
    trackers: workspace.trackers,
    now: clock(),
  );
  if (await sync()) await redraw();
}
