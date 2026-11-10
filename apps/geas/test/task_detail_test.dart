import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geas/state/sync.dart';
import 'package:geas_core/geas_core.dart';

import 'harness.dart';

void main() {
  late TestApp app;
  setUp(() => app = TestApp());

  Future<void> open(WidgetTester tester, String title, {String? list}) async {
    await app.seed();
    await app.pump(tester);
    if (list != null) {
      await tester.tap(find.text(list).first);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  Finder sheet() => find.byType(BottomSheet);
  Finder inSheet(Finder f) => find.descendant(of: sheet(), matching: f);

  Future<void> choose(WidgetTester tester, String chip, String item) async {
    await tester.tap(inSheet(find.text(chip)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    // Above the sheet, on the scrim over the task pane.
    await tester.tapAt(const Offset(700, 40));
    await tester.pumpAndSettle();
  }

  /// The task in the remote repo after the next sync.
  Future<Task> remote(WidgetTester tester, String title) async {
    await tester.pump(syncDelay);
    await tester.pumpAndSettle();
    return [
      for (final MapEntry(:key, :value) in app.github.files.entries)
        if (key.endsWith('.md')) Task.parse(utf8.decode(value)),
    ].singleWhere((t) => t.title == title);
  }

  testWidgets('renaming saves and syncs', (tester) async {
    await open(tester, 'Reply to the luthier');
    await tester.enterText(
      inSheet(find.byType(TextField)).first,
      'Reply to the luthier about frets',
    );
    await tester.pumpAndSettle();
    await close(tester);
    expect(find.text('Reply to the luthier about frets'), findsOneWidget);
    final task = await remote(tester, 'Reply to the luthier about frets');
    expect(task.updated.isAtSameMomentAs(now), isTrue);
  });

  testWidgets('priority and list from their menus', (tester) async {
    await open(tester, 'Reply to the luthier');
    await choose(tester, 'Low priority', 'High');
    expect(inSheet(find.text('High priority')), findsOneWidget);
    await choose(tester, 'Inbox', 'Home');
    expect(inSheet(find.text('Home')), findsOneWidget);
    await close(tester);
    expect(find.text('Reply to the luthier'), findsNothing); // left the inbox
    final task = await remote(tester, 'Reply to the luthier');
    expect((task.priority, task.list), (Priority.high, 'home'));
  });

  testWidgets('due date, time and no date', (tester) async {
    await open(tester, 'Reply to the luthier');
    await choose(tester, 'Add date', 'Tomorrow');
    expect(inSheet(find.text('Tomorrow')), findsOneWidget);

    await choose(tester, 'Tomorrow', 'Add a time…');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(inSheet(find.text('Tomorrow 09:00')), findsOneWidget);
    final due = (await remote(tester, 'Reply to the luthier')).due!;
    expect((due.date, due.hour), (const LocalDate(2026, 11, 9), 9));

    await choose(tester, 'Tomorrow 09:00', 'No date');
    expect(inSheet(find.text('Add date')), findsOneWidget);
  });

  testWidgets('adding and removing tags', (tester) async {
    await open(tester, 'Reply to the luthier');
    await tester.tap(inSheet(find.text('Add tag')));
    await tester.pumpAndSettle();
    expect(find.text('#errands'), findsWidgets); // known tags to pick
    await tester.enterText(find.byType(TextField).last, '#on hold');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(inSheet(find.text('#on-hold')), findsOneWidget);
    expect((await remote(tester, 'Reply to the luthier')).tags, ['on-hold']);

    await tester.tap(find.byTooltip('Remove #on-hold'));
    await tester.pumpAndSettle();
    expect(inSheet(find.text('#on-hold')), findsNothing);
  });

  testWidgets('checklist items and notes', (tester) async {
    await open(tester, 'Order 1N914s', list: 'Pedals');
    await tester.enterText(
      inSheet(find.widgetWithText(TextField, 'Add an item')),
      'buy flux',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(inSheet(find.text('buy flux')), findsOneWidget);

    await tester.tap(find.byTooltip('Remove item').first);
    await tester.pumpAndSettle();
    expect(inSheet(find.text('check Tayda stock')), findsNothing);

    await tester.tap(inSheet(find.textContaining('Need about 20')));
    await tester.pumpAndSettle();
    await tester.enterText(
      inSheet(find.byType(TextField)).last,
      'Need about 30.\n\n- [x] pick pots\n',
    );
    await tester.tap(inSheet(find.text('Done')));
    await tester.pumpAndSettle();
    expect(inSheet(find.text('Need about 30.')), findsOneWidget);
    expect(inSheet(find.text('buy flux')), findsNothing);
    expect(
      (await remote(tester, 'Order 1N914s')).body,
      'Need about 30.\n\n- [x] pick pots\n',
    );
  });

  testWidgets('deleting asks, then removes it everywhere', (tester) async {
    await open(tester, 'Reply to the luthier');
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(sheet(), findsNothing);
    expect(find.text('Reply to the luthier'), findsNothing);
    await tester.pump(syncDelay);
    await tester.pumpAndSettle();
    expect(app.remoteTitles(), isNot(contains('Reply to the luthier')));
  });
}
