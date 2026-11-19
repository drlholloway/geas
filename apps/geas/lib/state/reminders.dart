import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geas_core/geas_core.dart' hide Priority;
import 'package:timezone/timezone.dart' as tz;

/// Shows reminders as notifications on this device.
abstract interface class ReminderHost {
  /// Asks the system to let Geas show notifications; false if it won't.
  Future<bool> requestPermission();

  /// Replaces every reminder waiting to be shown with [reminders]. Ones
  /// already shown stay where they are.
  Future<void> schedule(List<Reminder> reminders);
}

/// Notifications through flutter_local_notifications. Android and macOS
/// hold the schedule themselves, so reminders arrive with Geas closed.
/// Linux has no scheduler, so there they're shown by timers and only while
/// Geas is open.
class LocalNotifications implements ReminderHost {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _ready;
  final _timers = <Timer>[];

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
  );

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
  Future<void> schedule(List<Reminder> reminders) async {
    await _init();
    if (Platform.isLinux) return _scheduleWithTimers(reminders);
    await _plugin.cancelAllPendingNotifications();
    for (final reminder in reminders) {
      try {
        await _plugin.zonedSchedule(
          id: reminder.id,
          title: reminder.title,
          body: reminder.body,
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

  void _scheduleWithTimers(List<Reminder> reminders) {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    final now = DateTime.now();
    for (final reminder in reminders) {
      final wait = reminder.at.difference(now);
      if (wait.isNegative) continue;
      _timers.add(
        Timer(
          wait,
          () => unawaited(
            _plugin.show(
              id: reminder.id,
              title: reminder.title,
              body: reminder.body,
              notificationDetails: _details,
            ),
          ),
        ),
      );
    }
  }
}

/// Sends [host] the reminders for what's in [workspace] at [now], or none
/// if reminders are [on] is false. Does nothing without a host.
Future<void> scheduleReminders(
  ReminderHost? host, {
  required bool on,
  required Iterable<Task> tasks,
  required Iterable<Tracker> trackers,
  required DateTime now,
}) async {
  if (host == null) return;
  await host.schedule(
    on
        ? upcomingReminders(tasks: tasks, trackers: trackers, now: now)
        : const [],
  );
}
