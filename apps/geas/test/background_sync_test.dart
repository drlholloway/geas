import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geas/state/background_sync.dart';
import 'package:geas_core/geas_core.dart';

import 'harness.dart';

void main() {
  late TestApp app;
  setUp(() async {
    app = TestApp()..homeWidget = FakeHomeWidget();
    await app.seed();
  });

  Future<BackgroundSync> run() =>
      backgroundSync(app.environment, clock: () => now);

  /// Adds a task to the remote, as another device would.
  void pushTask(String title, Priority priority) {
    final task = Task.create(title: title, now: now, priority: priority);
    app.github.push({taskPath(task, now): utf8.encode(task.encode())});
  }

  test('pulls other devices\' changes and redraws the widget', () async {
    expect(await run(), BackgroundSync.synced);
    expect(app.homeWidget!.titlesIn('doFirst'), ['Order 1N914s']);

    pushTask('Refill the prescription', Priority.high);
    expect(await run(), BackgroundSync.synced);
    expect(
      app.homeWidget!.titlesIn('doFirst'),
      containsAll(['Order 1N914s', 'Refill the prescription']),
    );
    final local = await Workspace.load(app.local.working);
    expect(
      local.tasks.map((t) => t.title),
      contains('Refill the prescription'),
    );
    expect(local.trackers, hasLength(2));
  });

  test('pushes edits left here by the widget while offline', () async {
    await run();
    final workspace = await Workspace.load(app.local.working);
    final task = workspace.tasks.singleWhere(
      (t) => t.title == 'Reply to the luthier',
    );
    await workspace.saveTask(task.complete(now), now: now);

    expect(await run(), BackgroundSync.synced);
    final remote = Task.parse(
      utf8.decode(app.github.files[taskPath(task.complete(now), now)]!),
    );
    expect(remote.isCompleted, isTrue);
  });

  test('offline, it leaves everything for the next run', () async {
    await run();
    final shown = app.homeWidget!.shown.length;
    app.offline = true;
    expect(await run(), BackgroundSync.failed);
    expect(app.homeWidget!.shown, hasLength(shown));
  });

  test('does nothing before setup or without a token', () async {
    app.tokens.tokens.clear();
    expect(await run(), BackgroundSync.notSetUp);
    app.config.config = null;
    expect(await run(), BackgroundSync.notSetUp);
    expect(app.homeWidget!.shown, isEmpty);
  });

  testWidgets('a running app is asked to sync instead', (tester) async {
    await app.pump(tester);
    pushTask('Refill the prescription', Priority.none);
    final result = await tester.runAsync(run);
    expect(result, BackgroundSync.handedToApp);
    await tester.pumpAndSettle();
    expect(find.text('Refill the prescription'), findsOneWidget);
  });
}
