import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geas/main.dart';
import 'package:geas/state/store.dart';
import 'package:geas/state/sync.dart';
import 'package:geas_core/geas_core.dart';

import 'harness.dart';

void main() {
  late TestApp app;
  setUp(() async {
    app = TestApp();
    await app.seed();
  });

  MapEntry<String, Task> remote(String title) => [
    for (final MapEntry(:key, :value) in app.github.files.entries)
      if (key.endsWith('.md')) MapEntry(key, Task.parse(utf8.decode(value))),
  ].singleWhere((e) => e.value.title == title);

  /// This device and another both retitle "Reply to the luthier"; this
  /// device's edit is newer, so it wins.
  Future<void> collide(WidgetTester tester) async {
    await app.pump(tester);
    final MapEntry(key: path, value: task) = remote('Reply to the luthier');
    ProviderScope.containerOf(tester.element(find.byType(GeasApp)))
        .read(taskStoreProvider.notifier)
        .edit(task.id, (t) => t.copyWith(title: 'Reply to the luthier today'));
    final other = task.copyWith(
      title: 'Write to the luthier',
      updated: now.subtract(const Duration(hours: 1)),
    );
    app.github.push({path: utf8.encode(other.encode())});
    await tester.tap(find.byTooltip('Sync now'));
    await tester.pumpAndSettle();
  }

  testWidgets('a conflict shows both sides and can swap them', (tester) async {
    await collide(tester);
    await tester.tap(find.textContaining('Sync kept one side of 1 conflict'));
    await tester.pumpAndSettle();
    expect(find.text('Conflicts'), findsWidgets);
    expect(find.textContaining('Both changed the title'), findsOneWidget);
    expect(find.text('Reply to the luthier today'), findsWidgets);
    expect(find.text('Write to the luthier'), findsOneWidget);

    await tester.tap(find.text('Use set-aside version'));
    await tester.pumpAndSettle();
    expect(find.text('No conflicts.'), findsOneWidget);
    expect(app.local.conflicts, isEmpty);
    await tester.pump(syncDelay);
    await tester.pumpAndSettle();
    expect(app.remoteTitles(), contains('Write to the luthier'));
    expect(app.remoteTitles(), isNot(contains('Reply to the luthier today')));
  });

  testWidgets('Keep this dismisses it', (tester) async {
    await collide(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conflicts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep this'));
    await tester.pumpAndSettle();
    expect(find.text('No conflicts.'), findsOneWidget);
    expect(find.textContaining('Sync kept one side'), findsNothing);
    expect(app.local.conflicts, isEmpty);
    expect(app.remoteTitles(), contains('Reply to the luthier today'));
  });

  testWidgets('an edit that beat a deletion can be deleted', (tester) async {
    final MapEntry(key: path, value: task) = remote('Clean the gutters');
    app.local.conflicts.add(
      SyncConflict(
        key: task.id,
        path: path,
        kind: ConflictKind.editedAndDeleted,
        detected: now,
        keptLocal: true,
      ),
    );
    await app.pump(tester);
    await tester.tap(find.textContaining('Sync kept one side'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Deleted on the other device'), findsOneWidget);
    await tester.tap(find.text('Delete it after all'));
    await tester.pumpAndSettle();
    expect(find.text('No conflicts.'), findsOneWidget);
    await tester.pump(syncDelay);
    await tester.pumpAndSettle();
    expect(app.remoteTitles(), isNot(contains('Clean the gutters')));
  });
}
