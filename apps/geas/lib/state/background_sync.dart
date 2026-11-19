import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:geas_core/geas_core.dart';
import 'package:workmanager/workmanager.dart';

import 'environment.dart';
import 'home_widget.dart';
import 'reminders.dart';
import 'sync_lock.dart';

/// The name Android's WorkManager knows the periodic sync by.
const backgroundSyncTask = 'dev.laneholloway.geas.sync';

/// The name the running app listens under for a background sync that came
/// due, as a `SendPort`; it replies true and syncs itself.
const syncPortName = 'geas.app.sync';

/// What a background sync did.
enum BackgroundSync {
  /// This device has no data repo or token yet.
  notSetUp,

  /// The app is running and was asked to sync instead.
  handedToApp,

  /// Synced, and the home-screen widget redrawn.
  synced,

  /// GitHub couldn't be reached or refused; the next run tries again.
  failed,
}

/// Schedules syncs for when the app is closed.
abstract interface class BackgroundScheduler {
  /// Syncs about every [every] from now on, or never if [on] is false.
  /// Safe to call on every launch.
  Future<void> apply({required bool on, required Duration every});
}

/// Android's WorkManager: runs [backgroundSyncDispatcher] about as often as
/// asked while there's a network, whether or not the app is open. Android
/// may put a run off to save battery.
class AndroidBackgroundScheduler implements BackgroundScheduler {
  const AndroidBackgroundScheduler();

  @override
  Future<void> apply({required bool on, required Duration every}) async {
    await Workmanager().initialize(backgroundSyncDispatcher);
    if (!on) return Workmanager().cancelByUniqueName(backgroundSyncTask);
    await Workmanager().registerPeriodicTask(
      backgroundSyncTask,
      backgroundSyncTask,
      frequency: every,
      constraints: Constraints(networkType: NetworkType.connected),
      // Keeps the schedule it has, but picks up a changed frequency.
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }
}

/// Runs in a background isolate each time the periodic sync comes due.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, input) async {
    // To the device log; there's no one else to tell, and the next run
    // tries again.
    try {
      final result = await backgroundSync(await AppEnvironment.platform());
      debugPrint('geas: background sync: ${result.name}');
    } on Object catch (e) {
      debugPrint('geas: background sync failed: $e');
    }
    return true;
  });
}

/// Syncs this device's copy with the data repo and redraws the home-screen
/// widget, so changes from other devices show without opening the app. If
/// the app is running it's asked to sync instead, so its copy stays
/// current and two syncs don't run on the same files.
Future<BackgroundSync> backgroundSync(
  AppEnvironment env, {
  DateTime Function() clock = DateTime.now,
}) async {
  final config = await env.config.load();
  if (config == null) return BackgroundSync.notSetUp;
  if (await askAppToSync()) return BackgroundSync.handedToApp;
  final token = await env.tokens.read(config.repo);
  if (token == null || token.isEmpty) return BackgroundSync.notSetUp;

  final store = env.openStore(config.repo);
  try {
    // Waits out a task being ticked off on the widget.
    await withSyncLock(
      Syncer(
        github: env.connect(config.repo, token),
        store: store,
        device: config.device,
        clock: clock,
      ).sync,
    );
  } on Exception {
    return BackgroundSync.failed;
  }
  final workspace = await Workspace.load(store.working);
  await showMatrix(
    env.homeWidget,
    workspace.tasks,
    now: clock(),
    warnDays: workspace.warnDays,
  );
  await showHealth(env.homeWidget, workspace.trackers, now: clock());
  // What other devices changed moves this one's reminders too.
  await scheduleReminders(
    env.reminders,
    on: config.reminders,
    tasks: workspace.tasks,
    trackers: workspace.trackers,
    now: clock(),
  );
  return BackgroundSync.synced;
}

/// Asks the running app, if it's listening, to sync, and waits for it to
/// say it will. False if there's no app or it didn't answer.
Future<bool> askAppToSync({Duration wait = const Duration(seconds: 2)}) async {
  final app = IsolateNameServer.lookupPortByName(syncPortName);
  if (app == null) return false;
  final reply = ReceivePort();
  try {
    app.send(reply.sendPort);
    return await reply.first.timeout(wait) == true;
  } on TimeoutException {
    // Registered by an app that has since closed.
    return false;
  } finally {
    reply.close();
  }
}
