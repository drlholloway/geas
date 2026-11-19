import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geas/state/background_sync.dart';
import 'package:geas/state/environment.dart';
import 'package:geas/state/home_widget.dart';
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
}
