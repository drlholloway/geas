import 'dart:convert';

import 'package:flutter/material.dart';
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
