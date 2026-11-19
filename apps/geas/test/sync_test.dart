import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geas/state/sync.dart';
import 'package:geas_core/geas_core.dart';

import 'harness.dart';

void main() {
  late TestApp app;
  setUp(() async {
    app = TestApp();
  });

  testWidgets('an edit goes out a few seconds later', (tester) async {
    await app.seed();
    await app.pump(tester);
    await tester.enterText(find.byType(TextField), 'Buy flux');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(app.remoteTitles(), isNot(contains('Buy flux')));

    await tester.pump(syncDelay);
    await tester.pumpAndSettle();
    expect(app.remoteTitles(), contains('Buy flux'));
    expect(app.github.commits.last, 'sync(testbox): 1 added');
  });

  testWidgets('the open app syncs on its own every half hour', (tester) async {
    await app.seed();
    await app.pump(tester);
    final task = Task.create(title: 'From the phone', now: now);
    app.github.push({taskPath(task, now): utf8.encode(task.encode())});
    await tester.pump(const Duration(minutes: 29));
    await tester.pumpAndSettle();
    expect(find.text('From the phone'), findsNothing);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(find.text('From the phone'), findsOneWidget);
  });

  testWidgets('Settings turns syncing on its own off, and sets how often', (
    tester,
  ) async {
    final scheduler = app.backgroundScheduler = FakeBackgroundScheduler();
    await app.seed();
    await app.pump(tester);
    expect(scheduler.applied, [(true, const Duration(minutes: 30))]);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.textContaining('even when Geas is closed'), findsOneWidget);
    await tester.tap(find.text('Every 30 minutes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every 2 hours').last);
    await tester.pumpAndSettle();
    expect(scheduler.applied.last, (true, const Duration(hours: 2)));
    expect(app.config.config!.syncMinutes, 120);
    expect(app.config.config!.toJson()['sync_minutes'], 120);

    await tester.tap(find.text('Sync on its own'));
    await tester.pumpAndSettle();
    expect(scheduler.applied.last.$1, isFalse);
    expect(app.config.config!.backgroundSync, isFalse);
    expect(find.text('How often'), findsNothing);

    // Off: nothing is pulled until asked.
    final task = Task.create(title: 'From the phone', now: now);
    app.github.push({taskPath(task, now): utf8.encode(task.encode())});
    await tester.pump(const Duration(hours: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();
    expect(app.remoteTitles(), contains('From the phone'));
    expect(find.text('From the phone'), findsNothing);
  });

  testWidgets('Sync now pulls changes from other devices', (tester) async {
    await app.seed();
    await app.pump(tester);
    final task = Task.create(title: 'From the phone', now: now);
    app.github.push({taskPath(task, now): utf8.encode(task.encode())});

    await tester.tap(find.byTooltip('Sync now'));
    await tester.pumpAndSettle();
    expect(find.text('From the phone'), findsOneWidget);
  });

  testWidgets('offline, edits stay here until GitHub is back', (tester) async {
    await app.seed();
    app.offline = true;
    await app.pump(tester);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Call the dentist'), findsNothing); // never synced

    await tester.enterText(find.byType(TextField), 'Buy flux');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump(syncDelay);
    await tester.pumpAndSettle();
    expect(find.text('Buy flux'), findsOneWidget);

    app.offline = false;
    await tester.tap(find.byTooltip('Sync now'));
    await tester.pumpAndSettle();
    expect(find.text('Synced just now'), findsOneWidget);
    expect(find.text('Call the dentist'), findsOneWidget);
    expect(app.remoteTitles(), contains('Buy flux'));
  });

  testWidgets('a rejected token points to settings', (tester) async {
    await app.seed();
    app.tokens.tokens[repo] = 'github_pat_revoked';
    app.otherToken = (_) => _Rejecting();
    await app.pump(tester);
    expect(find.text('Sync failed'), findsOneWidget);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.textContaining('GitHub rejected the token'), findsOneWidget);
    expect(find.textContaining('Replace it with a new one'), findsOneWidget);
  });
}

class _Rejecting implements GitHubClient {
  @override
  Object? noSuchMethod(Invocation invocation) =>
      Future<Never>.error(const GitHubException(401, 'Bad credentials'));
}
