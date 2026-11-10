import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geas/state/home_widget.dart';
import 'package:geas_core/geas_core.dart';

import 'harness.dart';
import 'sample_data.dart';

void main() {
  late TestApp app;
  setUp(() async {
    app = TestApp()..homeWidget = FakeHomeWidget();
    await app.seed();
  });

  FakeHomeWidget widget() => app.homeWidget!;

  Task remote(String title) => [
    for (final MapEntry(:key, :value) in app.github.files.entries)
      if (key.endsWith('.md')) Task.parse(utf8.decode(value)),
  ].singleWhere((t) => t.title == title);

  /// Lets the app settle and redraw the widget.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
  }

  test('the snapshot holds each quadrant, in order, with due dates', () {
    final snapshot = matrixSnapshot(
      sampleStore(now).tasks,
      now: now,
      warnDays: 3,
    );
    expect(snapshot['warn_days'], 3);
    final quadrants = (snapshot['quadrants']! as List)
        .cast<Map<String, Object?>>();
    expect(
      [for (final q in quadrants) q['title']],
      ['Do', 'Schedule', 'Delegate', 'Drop'],
    );
    final schedule = quadrants[1];
    expect(schedule['count'], 2);
    expect(schedule['priority'], 'medium');
    final [overdue, tomorrow] = (schedule['tasks']! as List)
        .cast<Map<String, Object?>>();
    expect(overdue['title'], 'Renew car registration');
    expect(overdue['day'], '2026-11-06');
    expect(overdue.containsKey('at'), isFalse);
    expect(tomorrow['day'], '2026-11-09');

    final drop = (quadrants[3]['tasks']! as List).cast<Map<String, Object?>>();
    final dentist = drop.singleWhere((t) => t['title'] == 'Call the dentist');
    expect(dentist['day'], '2026-11-08');
    expect(dentist['at'], DateTime(2026, 11, 8, 17).millisecondsSinceEpoch);
    expect(
      [for (final q in quadrants) ...(q['tasks']! as List)],
      isNot(
        contains(
          predicate<Map<String, Object?>>(
            (t) => t['title'] == 'Solder the fuzz board',
          ),
        ),
      ),
      reason: 'done tasks are left out',
    );
  });

  test('only geas://done/<id> links finish a task', () {
    expect(doneTaskId(Uri.parse('geas://done/01JC')), '01JC');
    expect(doneTaskId(Uri.parse('geas://task/01JC')), isNull);
    expect(doneTaskId(Uri.parse('other://done/01JC')), isNull);
    expect(doneTaskId(null), isNull);
  });

  testWidgets('the app keeps the widget current', (tester) async {
    await app.pump(tester);
    await settle(tester);
    expect(widget().titlesIn('doFirst'), ['Order 1N914s']);
    expect(widget().titlesIn('delegate'), ['Reply to the luthier']);

    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('Reply to the luthier'),
          matching: find.byType(ListTile),
        ),
        matching: find.byType(Checkbox),
      ),
    );
    await settle(tester);
    expect(widget().titlesIn('delegate'), isEmpty);
  });

  testWidgets('tapping a task on the widget opens it', (tester) async {
    await app.pump(tester);
    final id = remote('Draft the Geas sync design').id;
    widget().tap('geas://task/$id');
    await tester.pumpAndSettle();
    expect(find.text('Matrix'), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Draft the Geas sync design'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a widget tap can launch the app on a task', (tester) async {
    final id = remote('Draft the Geas sync design').id;
    widget().launchLink = Uri.parse('geas://task/$id');
    await app.pump(tester);
    await tester.pumpAndSettle();
    expect(find.byTooltip('All four on one screen'), findsOneWidget);
    // The sheet waited for the tasks, so its title is filled in.
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.widgetWithText(TextField, 'Draft the Geas sync design'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a widget tap can launch the app on the matrix', (tester) async {
    widget().launchLink = Uri.parse('geas://matrix');
    await app.pump(tester);
    await tester.pumpAndSettle();
    expect(find.byTooltip('All four on one screen'), findsOneWidget);
  });

  testWidgets('a task ticked on the widget goes to the running app', (
    tester,
  ) async {
    await app.pump(tester);
    await settle(tester);
    final id = remote('Reply to the luthier').id;
    final taken = await tester.runAsync(() => handToApp(id));
    expect(taken, isTrue);
    await settle(tester);
    expect(find.text('Reply to the luthier'), findsNothing);
    expect(widget().titlesIn('delegate'), isEmpty);

    await tester.pump(const Duration(seconds: 6)); // the sync delay
    await tester.pumpAndSettle();
    expect(remote('Reply to the luthier').isCompleted, isTrue);
  });

  /// This device's copy, synced, as it is after the app has run.
  Future<void> syncDevice() => Syncer(
    github: app.github,
    store: app.local,
    device: app.hostname,
    clock: () => now,
  ).sync();

  test('with no app running, the background finishes and syncs it', () async {
    await syncDevice();
    final id = remote('Reply to the luthier').id;
    await completeFromWidget(id, app.environment, clock: () => now);
    expect(remote('Reply to the luthier').isCompleted, isTrue);
    expect(widget().shown, hasLength(2)); // before and after the sync
    expect(widget().titlesIn('delegate'), isEmpty);
  });

  test('a task not in this copy yet is fetched first', () async {
    final id = remote('Reply to the luthier').id;
    await completeFromWidget(id, app.environment, clock: () => now);
    expect(remote('Reply to the luthier').isCompleted, isTrue);
  });

  test('offline, the background finishes it here for the next sync', () async {
    await syncDevice();
    final id = remote('Reply to the luthier').id;
    app.offline = true;
    await completeFromWidget(id, app.environment, clock: () => now);
    expect(remote('Reply to the luthier').isCompleted, isFalse);
    expect(widget().titlesIn('delegate'), isEmpty);
    final local = await Workspace.load(app.local.working);
    expect(local.task(id)!.isCompleted, isTrue);

    app.offline = false;
    await syncDevice();
    expect(remote('Reply to the luthier').isCompleted, isTrue);
  });
}
