import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'background_sync.dart';
import 'environment.dart';

/// The argument that starts Geas with no window, to sync and quit. The
/// macOS launch agent and the Linux systemd timer pass it.
const backgroundSyncFlag = '--background-sync';

/// How often the macOS launch agent starts Geas. It can't be changed after
/// the app is built, so each start checks whether a sync is due yet.
const macAgentEvery = Duration(minutes: 15);

/// A lock file held for as long as a window of Geas is open, so a
/// background start can tell and leave the syncing to it. File locks are
/// per process, which is what's wanted here: the two are separate
/// processes.
class AppLock {
  AppLock._(this._file);

  final RandomAccessFile _file;

  /// Takes the lock in [supportDir], or returns null if another Geas has
  /// it.
  static Future<AppLock?> take(String supportDir) async {
    await Directory(supportDir).create(recursive: true);
    final file = await File(p.join(supportDir, 'app.lock'))
        .open(mode: FileMode.write);
    try {
      await file.lock(FileLock.exclusive);
      return AppLock._(file);
    } on FileSystemException {
      await file.close();
      return null;
    }
  }

  Future<void> release() async {
    await _file.unlock();
    await _file.close();
  }
}

/// What a background start did.
enum BackgroundRun {
  /// A window of Geas is open; it syncs on its own.
  appOpen,

  /// Syncing on its own is turned off, or this device isn't set up.
  off,

  /// The last sync was less than the chosen interval ago.
  notDue,

  /// It synced (or tried to).
  ran,
}

/// Syncs once, as Geas started with [backgroundSyncFlag] does: unless a
/// window is open, syncing on its own is off, or it synced more recently
/// than the device's interval. When it last ran is kept in
/// `background.json` in [supportDir].
Future<BackgroundRun> runDesktopBackgroundSync(
  AppEnvironment env,
  String supportDir, {
  DateTime Function() clock = DateTime.now,
}) async {
  final lock = await AppLock.take(supportDir);
  if (lock == null) return BackgroundRun.appOpen;
  try {
    final config = await env.config.load();
    if (config == null || !config.backgroundSync) return BackgroundRun.off;

    final record = File(p.join(supportDir, 'background.json'));
    final now = clock();
    try {
      final last = DateTime.parse(
        (jsonDecode(await record.readAsString()) as Map)['last'] as String,
      );
      // A minute's grace, as the agent's starts aren't to the second.
      final due = last.add(
        Duration(minutes: config.syncMinutes) - const Duration(minutes: 1),
      );
      if (now.isBefore(due) && !now.isBefore(last)) return BackgroundRun.notDue;
    } on Object {
      // Never ran, or unreadable: run now.
    }
    await backgroundSync(env, clock: clock);
    await record.writeAsString(
      jsonEncode({'last': now.toUtc().toIso8601String()}),
    );
    return BackgroundRun.ran;
  } finally {
    await lock.release();
  }
}

/// macOS: the launch agent inside the app bundle, turned on and off through
/// the system's SMAppService. Once on, macOS starts Geas with no window
/// every [macAgentEvery], whether or not it's open. Needs macOS 13.
class MacAgentScheduler implements BackgroundScheduler {
  const MacAgentScheduler();

  @override
  String get where =>
      'In the background, even when Geas is closed. macOS lists Geas under '
      'Login Items & Extensions in System Settings, where it can also be '
      'turned off.';

  static const _channel = MethodChannel('dev.laneholloway.geas/background');

  @override
  Future<void> apply({required bool on, required Duration every}) async {
    try {
      await _channel.invokeMethod<bool>('set', on);
    } on PlatformException catch (e) {
      debugPrint('geas: launch agent: ${e.message} (${e.details})');
    } on MissingPluginException {
      // An older build of the runner.
    }
  }
}

/// Runs a program and gives its exit code. Tests swap in a fake.
typedef RunCommand = Future<int> Function(String program, List<String> args);

Future<int> _run(String program, List<String> args) async =>
    (await Process.run(program, args)).exitCode;

/// Linux: a systemd user timer that starts Geas with no window every so
/// often, whether or not it's open. Its two unit files are written to the
/// user's systemd directory and rewritten on every launch, so they follow
/// the app if it moves.
///
/// The timer runs inside the desktop session, since Geas needs a display
/// to start even when it shows nothing.
class LinuxSystemdScheduler implements BackgroundScheduler {
  LinuxSystemdScheduler({String? unitDir, String? executable, RunCommand? run})
    : unitDir = unitDir ?? _defaultUnitDir(),
      // An AppImage runs from a mount that's gone once it quits; the
      // image itself is what to start.
      executable =
          executable ??
          Platform.environment['APPIMAGE'] ??
          Platform.resolvedExecutable,
      _runCommand = run ?? _run;

  static const service = 'geas-sync.service';
  static const timer = 'geas-sync.timer';

  /// Where systemd looks for a user's units.
  final String unitDir;

  /// What the timer starts.
  final String executable;
  final RunCommand _runCommand;

  static String _defaultUnitDir() {
    final env = Platform.environment;
    final config = env['XDG_CONFIG_HOME'];
    return p.join(
      config != null && config.isNotEmpty
          ? config
          : p.join(env['HOME'] ?? '', '.config'),
      'systemd',
      'user',
    );
  }

  @override
  String get where =>
      'In the background, even when Geas is closed, through a systemd '
      'timer (geas-sync.timer) while you\'re logged in.';

  /// The unit that runs one sync.
  String serviceUnit() =>
      '[Unit]\n'
      'Description=Geas background sync\n'
      '\n'
      '[Service]\n'
      'Type=oneshot\n'
      // Quoted, as the path may have spaces; % is systemd's own escape.
      'ExecStart="${executable.replaceAll('%', '%%').replaceAll('"', r'\"')}" '
      '$backgroundSyncFlag\n'
      'TimeoutStartSec=120\n';

  /// The unit that runs it [every] so often.
  String timerUnit(Duration every) =>
      '[Unit]\n'
      'Description=Sync Geas every ${every.inMinutes} minutes\n'
      '\n'
      '[Timer]\n'
      'OnStartupSec=2min\n'
      'OnUnitActiveSec=${every.inMinutes}min\n'
      '\n'
      '[Install]\n'
      'WantedBy=timers.target\n';

  @override
  Future<void> apply({required bool on, required Duration every}) async {
    final serviceFile = File(p.join(unitDir, service));
    final timerFile = File(p.join(unitDir, timer));
    try {
      if (on) {
        await Directory(unitDir).create(recursive: true);
        await serviceFile.writeAsString(serviceUnit());
        await timerFile.writeAsString(timerUnit(every));
        await _runCommand('systemctl', ['--user', 'daemon-reload']);
        await _runCommand('systemctl', ['--user', 'enable', '--now', timer]);
        // Picks up a changed interval on a timer that was already running.
        await _runCommand('systemctl', ['--user', 'restart', timer]);
      } else if (await timerFile.exists() || await serviceFile.exists()) {
        await _runCommand('systemctl', ['--user', 'disable', '--now', timer]);
        if (await timerFile.exists()) await timerFile.delete();
        if (await serviceFile.exists()) await serviceFile.delete();
        await _runCommand('systemctl', ['--user', 'daemon-reload']);
      }
    } on Exception catch (e) {
      // No systemd here (or no user session): the app still syncs while
      // it's open.
      debugPrint('geas: systemd timer: $e');
    }
  }
}
