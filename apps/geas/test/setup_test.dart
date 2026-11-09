import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geas_core/geas_core.dart';

import 'harness.dart';

void main() {
  late TestApp app;
  setUp(() => app = TestApp());

  Finder field(String label) => find.widgetWithText(TextField, label);

  /// Scrolls [finder] into view, then taps it.
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
  }

  Future<void> fillIn(WidgetTester tester, {String token = goodToken}) async {
    await tester.enterText(field('GitHub account'), 'drl');
    await tester.ensureVisible(field('Paste the token'));
    await tester.enterText(field('Paste the token'), token);
    await tester.pump();
  }

  testWidgets('first run sets up the repo, token and device', (tester) async {
    await app.pump(tester);
    expect(find.text('Set up Geas'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'testbox'), findsOneWidget);

    await fillIn(tester);
    await tap(tester, find.text('Create it on GitHub'));
    await tap(tester, find.text('Open the token form'));
    await tester.pump();
    expect(app.openedUrls.map((u) => u.path), [
      '/new',
      '/settings/personal-access-tokens/new',
    ]);
    expect(
      app.openedUrls.last.queryParameters['name'],
      'Geas testbox 2026-11-08',
    );

    await tap(tester, find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Inbox'), findsWidgets);
    expect(find.text('Synced just now'), findsOneWidget);
    expect(app.tokens.tokens[repo], goodToken);
    expect(app.config.config!.repo, repo);
    expect(app.config.config!.device, 'testbox');
    expect(app.github.files.keys, contains(repoConfigPath));
  });

  testWidgets('a token that can\'t see the repo gets advice', (tester) async {
    await app.pump(tester);
    await fillIn(tester, token: 'github_pat_wrong_repo');
    await tap(tester, find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.textContaining('The token can\'t see $repo'), findsOneWidget);
    expect(app.tokens.tokens, isEmpty);
    expect(app.config.config, isNull);

    // Paste the right one and go on.
    await tester.enterText(field('Paste the token'), goodToken);
    await tester.pump();
    await tap(tester, find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Inbox'), findsWidgets);
  });

  testWidgets('a classic token gets a warning', (tester) async {
    await app.pump(tester);
    await fillIn(tester, token: 'ghp_classic');
    expect(find.textContaining('That\'s a classic token'), findsOneWidget);
  });

  testWidgets('replacing the token from settings', (tester) async {
    await app.seed(tokenExpires: now.add(const Duration(days: 3)));
    await app.pump(tester);
    expect(find.textContaining('expires in 3 days'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(find.text('A new token for $repo'), findsOneWidget);

    app.github.access = RepoAccess(
      canWrite: true,
      tokenExpires: now.add(const Duration(days: 366)),
    );
    await tester.enterText(field('Paste the token'), goodToken);
    await tester.pump();
    await tap(tester, find.widgetWithText(FilledButton, 'Replace'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
    expect(find.textContaining('Token replaced'), findsOneWidget);
    expect(find.textContaining('expires in'), findsNothing);
    expect(app.config.config!.tokenExpires, now.add(const Duration(days: 366)));
  });

  testWidgets('disconnecting goes back to setup', (tester) async {
    await app.seed();
    await app.pump(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tap(tester, find.text('Disconnect'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Disconnect'));
    await tester.pumpAndSettle();
    expect(find.text('Set up Geas'), findsOneWidget);
    expect(app.tokens.tokens, isEmpty);
    expect(app.config.config, isNull);
  });
}
