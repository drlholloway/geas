import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geas_core/geas_core.dart' hide Priority;
import 'package:path/path.dart' as p;
import 'package:timezone/timezone.dart' as tz;

import 'desktop_background.dart';

/// A reminder that was tapped: which one, and the time it was for.
typedef ReminderTap = ({String key, DateTime at});

/// Shows reminders as notifications on this device.
abstract interface class ReminderHost {
  /// Asks the system to let Geas show notifications; false if it won't.
  Future<bool> requestPermission();

  /// Brings this device's notifications in line with the data:
  ///
  /// - [upcoming] replaces every reminder waiting to be shown;
  /// - a notification already on screen stays only if it's for one of
  ///   [standing], so finishing a task or dismissing its reminder on
  ///   another device clears it here;
  /// - where the system can't hold a schedule itself (Linux), any of
  ///   [standing] that came due since this was last called is shown now.
  Future<void> schedule(
    List<Reminder> upcoming, {
    List<Reminder> standing = const [],
  });

  /// Reminders tapped while the app is running.
  Stream<ReminderTap> get taps;

  /// The reminder whose tap launched the app, if one did.
  Future<ReminderTap?> launchedFrom();
}

/// What a notification carries so a tap can be traced to its reminder.
String reminderPayload(Reminder reminder) =>
    '${reminder.key}|${reminder.at.millisecondsSinceEpoch}';

/// Reads [reminderPayload] back, or null if [payload] isn't one.
ReminderTap? parseReminderPayload(String? payload) {
  final bar = payload?.lastIndexOf('|') ?? -1;
  final at = bar < 1 ? null : int.tryParse(payload!.substring(bar + 1));
  if (at == null) return null;
  return (
    key: payload!.substring(0, bar),
    at: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
  );
}

/// Linux: asks systemd to start Geas, with no window, when the next
/// reminder is due, so it's shown even if Geas is closed by then. A
/// one-off timer unit, `geas-reminder`, replaced each time.
class LinuxReminderWake {
  LinuxReminderWake({String? executable, RunCommand? run})
    : executable =
          executable ??
          Platform.environment['APPIMAGE'] ??
          Platform.resolvedExecutable,
      _run = run ?? _runProcess;

  static const unit = 'geas-reminder';

  final String executable;
  final RunCommand _run;

  static Future<int> _runProcess(String program, List<String> args) async =>
      (await Process.run(program, args)).exitCode;

  /// The arguments to `systemd-run` that start Geas at [when], local time.
  List<String> runArguments(DateTime when) {
    final t = when.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return [
      '--user',
      '--unit=$unit',
      '--collect',
      '--timer-property=AccuracySec=1s',
      '--on-calendar=${t.year}-${two(t.month)}-${two(t.day)} '
          '${two(t.hour)}:${two(t.minute)}:${two(t.second)}',
      executable,
      backgroundSyncFlag,
    ];
  }

  /// Wakes Geas at [when], in place of any wake set before; none if null.
  Future<void> set(DateTime? when) async {
    try {
      await _run('systemctl', ['--user', 'stop', '$unit.timer']);
      if (when != null) await _run('systemd-run', runArguments(when));
    } on Exception catch (e) {
      // No systemd: reminders still show while Geas is open.
      debugPrint('geas: reminder wake: $e');
    }
  }
}

/// Notifications through flutter_local_notifications. Android and macOS
/// hold the schedule themselves, so reminders arrive with Geas closed.
/// Linux has no scheduler: there Geas shows them itself, by timers while
/// it's open, and by having systemd start it when the next one is due
/// ([LinuxReminderWake]) while it's closed.
class LocalNotifications implements ReminderHost {
  LocalNotifications({this.supportDir, this.linuxWake});

  /// Where Linux keeps the time it last showed reminders up to.
  final String? supportDir;

  /// Wakes Geas for the next reminder on Linux; null elsewhere, and in
  /// debug builds.
  final LinuxReminderWake? linuxWake;

  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _ready;
  final _timers = <Timer>[];
  final _taps = StreamController<ReminderTap>.broadcast();

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription:
          'Tasks coming due, and medications and sensors due again.',
      importance: Importance.high,
      priority: Priority.high,
    ),
    macOS: DarwinNotificationDetails(),
    linux: LinuxNotificationDetails(),
  );

  Future<void> _init() => _ready ??= _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
      // Permission is asked for when reminders are turned on, not here.
      macOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      linux: LinuxInitializationSettings(defaultActionName: 'Open Geas'),
    ),
    onDidReceiveNotificationResponse: (response) {
      final tap = parseReminderPayload(response.payload);
      if (tap != null) _taps.add(tap);
    },
  );

  @override
  Stream<ReminderTap> get taps => _taps.stream;

  @override
  Future<ReminderTap?> launchedFrom() async {
    await _init();
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return null;
      return parseReminderPayload(details.notificationResponse?.payload);
    } on Object {
      // Not every platform can say.
      return null;
    }
  }

  @override
  Future<bool> requestPermission() async {
    await _init();
    if (Platform.isAndroid) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (Platform.isMacOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, sound: true) ??
          false;
    }
    return true;
  }

  @override
  Future<void> schedule(
    List<Reminder> upcoming, {
    List<Reminder> standing = const [],
  }) async {
    await _init();
    await _clearExcept({for (final reminder in standing) reminder.id});
    if (Platform.isLinux) return _scheduleOnLinux(upcoming, standing);
    await _plugin.cancelAllPendingNotifications();
    for (final reminder in upcoming) {
      try {
        await _plugin.zonedSchedule(
          id: reminder.id,
          title: reminder.title,
          body: reminder.body,
          payload: reminderPayload(reminder),
          // An instant, so no time zone database is needed.
          scheduledDate: tz.TZDateTime.from(reminder.at, tz.UTC),
          notificationDetails: _details,
          // Within a few minutes; exact alarms need a permission of their
          // own on Android.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } on Exception catch (e) {
        // Passed while this ran, or the system refused it: skip it.
        debugPrint('geas: reminder ${reminder.key}: $e');
      }
    }
  }

  /// Takes down notifications on screen that aren't for one of [keep].
  Future<void> _clearExcept(Set<int> keep) async {
    try {
      for (final shown in await _plugin.getActiveNotifications()) {
        final id = shown.id;
        if (id != null && !keep.contains(id)) await _plugin.cancel(id: id);
      }
    } on Object {
      // Linux can't list what's on screen; nothing is cleared there.
    }
  }

  Future<void> _show(Reminder reminder) => _plugin.show(
    id: reminder.id,
    title: reminder.title,
    body: reminder.body,
    payload: reminderPayload(reminder),
    notificationDetails: _details,
  );

  File? get _shownFile => supportDir == null
      ? null
      : File(p.join(supportDir!, 'reminders_shown.json'));

  /// The time reminders have been shown up to, or null on the first run.
  Future<DateTime?> _shownUpTo() async {
    try {
      final json = jsonDecode(await _shownFile!.readAsString()) as Map;
      return DateTime.parse(json['up_to'] as String);
    } on Object {
      return null;
    }
  }

  Future<void> _setShownUpTo(DateTime time) async {
    try {
      await _shownFile?.writeAsString(
        jsonEncode({'up_to': time.toUtc().toIso8601String()}),
      );
    } on Exception catch (e) {
      debugPrint('geas: reminders: $e');
    }
  }

  Future<void> _scheduleOnLinux(
    List<Reminder> upcoming,
    List<Reminder> standing,
  ) async {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    final now = DateTime.now();
    // Whatever came due since the last look, as when systemd woke Geas for
    // it or Geas was closed over it. Nothing on the very first look.
    final since = await _shownUpTo();
    if (since != null) {
      for (final reminder in standing) {
        if (reminder.at.isAfter(since)) await _show(reminder);
      }
    }
    await _setShownUpTo(now);

    for (final reminder in upcoming) {
      final wait = reminder.at.difference(now);
      if (wait.isNegative) continue;
      _timers.add(
        Timer(wait, () async {
          await _show(reminder);
          await _setShownUpTo(reminder.at);
        }),
      );
    }
    // A second past it, so it has come due by the time Geas looks.
    await linuxWake?.set(
      upcoming.isEmpty
          ? null
          : upcoming.first.at.add(const Duration(seconds: 1)),
    );
  }
}

/// Sends [host] the reminders for [tasks] and [trackers] at [now], or
/// clears them all if reminders are off ([on] false). [dayMinutes] is when
/// a task with no time is announced, in minutes past midnight, and
/// [dismissed] what any device has acknowledged. Does nothing without a
/// host.
Future<void> scheduleReminders(
  ReminderHost? host, {
  required bool on,
  required Iterable<Task> tasks,
  required Iterable<Tracker> trackers,
  required DateTime now,
  int dayMinutes = reminderHour * 60,
  Dismissals dismissed = const Dismissals(),
}) async {
  if (host == null) return;
  if (!on) return host.schedule(const []);
  await host.schedule(
    upcomingReminders(
      tasks: tasks,
      trackers: trackers,
      now: now,
      dayMinutes: dayMinutes,
    ),
    standing: standingReminders(
      tasks: tasks,
      trackers: trackers,
      now: now,
      dayMinutes: dayMinutes,
      dismissed: dismissed,
    ),
  );
}
