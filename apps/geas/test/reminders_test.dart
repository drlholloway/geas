import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geas/state/background_sync.dart';
import 'package:geas/state/environment.dart';
import 'package:geas/state/home_widget.dart';
import 'package:geas/state/reminders.dart';
import 'package:geas_core/geas_core.dart';
import 'package:material_ui/material_ui.dart';

import 'harness.dart';

void main() {
  late TestApp app;
  late FakeReminders reminders;
  setUp(() async {
    app = TestApp();
    reminders = app.reminders = FakeReminders();
    await app.seed();
  });

  /// Lets the app settle and set its reminders.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> turnOn(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remind me'));
    await settle(tester);
  }

  testWidgets('off until turned on in Settings, which asks permission', (
    tester,
  ) async {
    await app.pump(tester);
    await settle(tester);
    expect(reminders.schedules.last, isEmpty);
    expect(reminders.asked, 0);

    await turnOn(tester);
    expect(reminders.asked, 1);
    expect(app.config.config!.reminders, isTrue);
    expect(app.config.config!.toJson()['reminders'], isTrue);
    // Sunday noon: the dentist at 17:00, tomorrow's and later ones at 9,
    // the sensor due Saturday, and Metformin has no interval.
    expect(reminders.titles, [
      'Call the dentist',
      'Draft the Geas sync design',
      'Pick up bass strings',
      'CGM sensor',
      'Clean the gutters',
    ]);
    expect(reminders.schedules.last.first.at, DateTime(2026, 11, 8, 17));

    await tester.tap(find.text('Remind me'));
    await settle(tester);
    expect(reminders.schedules.last, isEmpty);
    expect(app.config.config!.reminders, isFalse);
  });

  testWidgets('refused permission leaves them off and says why', (
    tester,
  ) async {
    reminders.allowed = false;
    await app.pump(tester);
    await turnOn(tester);
    expect(app.config.config!.reminders, isFalse);
    expect(
      find.textContaining('Notifications are turned off for Geas'),
      findsOneWidget,
    );
  });

  testWidgets('finishing a task drops its reminder; logging moves one', (
    tester,
  ) async {
    app.config.config = app.config.config!.copyWith(reminders: true);
    await app.pump(tester);
    await settle(tester);
    expect(reminders.titles, contains('Draft the Geas sync design'));

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Draft the Geas sync design'),
        matching: find.byType(Checkbox),
      ),
    );
    await settle(tester);
    expect(reminders.titles, isNot(contains('Draft the Geas sync design')));

    await tester.tap(find.text('Health'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Replace'));
    await settle(tester);
    final sensor = reminders.schedules.last.singleWhere(
      (r) => r.key == 'tracker:cgm-sensor',
    );
    expect(sensor.at.toLocal(), now.add(const Duration(days: 10)));
    expect(sensor.body, 'Time to replace it');
  });

  test('a background sync sets reminders from what it pulled', () async {
    app.config.config = app.config.config!.copyWith(reminders: true);
    final task = Task.create(
      title: 'From the phone',
      now: now,
      due: Due.date(LocalDate.of(now).addDays(1)),
    );
    app.github.push({taskPath(task, now): utf8.encode(task.encode())});
    await backgroundSync(app.environment, clock: () => now);
    expect(reminders.titles, contains('From the phone'));

    // Finished on the widget: gone again.
    await completeFromWidget(task.id, app.environment, clock: () => now);
    expect(reminders.titles, isNot(contains('From the phone')));
  });

  test('with reminders off the background sets none', () async {
    await backgroundSync(app.environment, clock: () => now);
    expect(reminders.schedules.last, isEmpty);
  });

  test('the setting survives a round trip, and defaults to off', () {
    const config = AppConfig(repo: repo, device: 'x');
    expect(config.reminders, isFalse);
    expect(config.toJson().containsKey('reminders'), isFalse);
    final on = AppConfig.fromJson(config.copyWith(reminders: true).toJson());
    expect(on.reminders, isTrue);
  });

  group('dismissing', () {
    final overdueAt = DateTime(2026, 11, 6, 9);

    testWidgets('a tap dismisses it everywhere and opens what it\'s about', (
      tester,
    ) async {
      app.config.config = app.config.config!.copyWith(reminders: true);
      await app.pump(tester);
      await settle(tester);
      // The overdue registration and this morning's order still stand.
      expect(
        [for (final r in reminders.standing.last) r.title],
        ['Renew car registration', 'Order 1N914s'],
      );
      final renew = reminders.standing.last.first;
      expect(renew.at, overdueAt);

      reminders.tap(renew.key, renew.at);
      await settle(tester);
      expect(
        [for (final r in reminders.standing.last) r.title],
        ['Order 1N914s'],
      );
      // Its sheet is open.
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.widgetWithText(TextField, 'Renew car registration'),
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      final remote = Dismissals.parse(
        utf8.decode(app.github.files[dismissedPath]!),
      );
      expect(remote.times[renew.key], overdueAt.toUtc());
    });

    testWidgets('a tap on a tracker\'s reminder opens it in Health', (
      tester,
    ) async {
      app.config.config = app.config.config!.copyWith(reminders: true);
      reminders.launchTap = (
        key: 'tracker:cgm-sensor',
        at: DateTime(2026, 11, 4, 9, 5),
      );
      await app.pump(tester);
      await settle(tester);
      expect(find.widgetWithText(AppBar, 'CGM sensor'), findsOneWidget);
    });

    test('one dismissed on another device is cleared here on sync', () async {
      app.config.config = app.config.config!.copyWith(reminders: true);
      await backgroundSync(app.environment, clock: () => now);
      final renew = reminders.standing.last.first;
      expect(renew.title, 'Renew car registration');

      app.github.push({
        dismissedPath: utf8.encode(
          const Dismissals().dismiss(renew.key, renew.at, now: now).encode(),
        ),
      });
      await backgroundSync(app.environment, clock: () => now);
      expect(
        [for (final r in reminders.standing.last) r.title],
        ['Order 1N914s'],
      );
    });
  });

  testWidgets('the time for tasks with no time is this device\'s choice', (
    tester,
  ) async {
    app.config.config = app.config.config!.copyWith(
      reminders: true,
      reminderMinutes: 7 * 60 + 30,
    );
    await app.pump(tester);
    await settle(tester);
    final tomorrow = reminders.schedules.last.singleWhere(
      (r) => r.title == 'Draft the Geas sync design',
    );
    expect(tomorrow.at, DateTime(2026, 11, 9, 7, 30));

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Tasks with no time'), findsOneWidget);
    expect(find.text('07:30'), findsOneWidget);
    expect(app.config.config!.toJson()['reminder_minutes'], 450);
  });

  test('a notification\'s payload names its reminder', () {
    final reminder = Reminder(
      key: 'task:01ABC',
      title: 't',
      body: 'b',
      at: DateTime.utc(2026, 11, 8, 15),
    );
    final tap = parseReminderPayload(reminderPayload(reminder))!;
    expect((tap.key, tap.at), ('task:01ABC', DateTime.utc(2026, 11, 8, 15)));
    expect(parseReminderPayload(null), isNull);
    expect(parseReminderPayload('nonsense'), isNull);
  });

  test(
    'on Linux, systemd is asked to wake Geas for the next reminder',
    () async {
      final commands = <String>[];
      final wake = LinuxReminderWake(
        executable: '/opt/Geas.AppImage',
        run: (program, args) async {
          commands.add('$program ${args.join(' ')}');
          return 0;
        },
      );
      await wake.set(DateTime(2026, 11, 8, 17, 0, 1));
      expect(commands, [
        'systemctl --user stop geas-reminder.timer',
        'systemd-run --user --unit=geas-reminder --collect '
            '--timer-property=AccuracySec=1s '
            '--on-calendar=2026-11-08 17:00:01 '
            '/opt/Geas.AppImage --background-sync',
      ]);
      commands.clear();
      await wake.set(null);
      expect(commands, ['systemctl --user stop geas-reminder.timer']);
    },
  );
}
