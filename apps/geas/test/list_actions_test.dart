import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geas/features/shell/sidebar.dart';
import 'package:geas/state/sync.dart';
import 'package:geas_core/geas_core.dart';

import 'harness.dart';

void main() {
  late TestApp app;
  setUp(() async {
    app = TestApp();
    await app.seed();
  });

  Finder inSidebar(String text) =>
      find.descendant(of: find.byType(Sidebar), matching: find.text(text));
  Finder appBar(String text) =>
      find.descendant(of: find.byType(AppBar), matching: find.text(text));

  Future<void> go(WidgetTester tester, String text) async {
    await tester.tap(inSidebar(text));
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester, String tooltip, String item) async {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item));
    await tester.pumpAndSettle();
  }

  Future<void> synced(WidgetTester tester) async {
    await tester.pump(syncDelay);
    await tester.pumpAndSettle();
  }

  Map<String, Object?> remoteList(String id) {
    final bytes = app.github.files['lists/$id.yaml'];
    if (bytes == null) return const {};
    final list = TaskList.parse(utf8.decode(bytes));
    return {'name': list.name, 'color': list.color};
  }

  List<Task> remoteTasks() => [
    for (final MapEntry(:key, :value) in app.github.files.entries)
      if (key.endsWith('.md')) Task.parse(utf8.decode(value)),
  ];

  testWidgets('adding a list shows it and syncs it', (tester) async {
    await app.pump(tester);
    await tester.tap(find.byTooltip('Add list'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Bass Builds');
    await tester.tap(find.byTooltip('#7E57C2'));
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(inSidebar('Bass Builds'), findsOneWidget);
    expect(appBar('Bass Builds'), findsOneWidget);
    await synced(tester);
    expect(remoteList('bass-builds'), {
      'name': 'Bass Builds',
      'color': '#7E57C2',
    });
  });

  testWidgets('a list name in use is refused', (tester) async {
    await app.pump(tester);
    await tester.tap(find.byTooltip('Add list'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'pedals');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('There is already a list called "pedals".'), findsOne);
  });

  testWidgets('editing a list renames and recolors it', (tester) async {
    await app.pump(tester);
    await go(tester, 'Pedals');
    await menu(tester, 'List options', 'Edit list');
    await tester.enterText(find.byType(TextField).last, 'Effects');
    await tester.tap(find.byTooltip('No color'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(inSidebar('Effects'), findsOneWidget);
    expect(appBar('Effects'), findsOneWidget);
    await synced(tester);
    expect(remoteList('pedals'), {'name': 'Effects', 'color': null});
  });

  testWidgets('deleting a list moves its tasks to the inbox', (tester) async {
    await app.pump(tester);
    await go(tester, 'Home');
    await menu(tester, 'List options', 'Delete list');
    expect(find.textContaining('Its 3 tasks move to the Inbox'), findsOne);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(inSidebar('Home'), findsNothing);
    expect(appBar('Inbox'), findsOneWidget);
    expect(find.text('Fix the squeaky door'), findsOneWidget);
    await synced(tester);
    expect(app.github.files.containsKey('lists/home.yaml'), isFalse);
    expect(
      remoteTasks().singleWhere((t) => t.title == 'Fix the squeaky door').list,
      inboxId,
    );
  });

  testWidgets('the inbox can be edited but not deleted', (tester) async {
    await app.pump(tester);
    await tester.tap(find.byTooltip('List options'));
    await tester.pumpAndSettle();
    expect(find.text('Edit list'), findsOneWidget);
    expect(find.text('Delete list'), findsNothing);
  });

  testWidgets('renaming a tag changes every task with it', (tester) async {
    await app.pump(tester);
    await go(tester, '#errands');
    await menu(tester, 'Tag options', 'Rename tag');
    await tester.enterText(find.byType(TextField).last, 'chores');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(appBar('#chores'), findsOneWidget);
    expect(find.text('Call the dentist'), findsOneWidget);
    expect(inSidebar('#errands'), findsNothing);
    await synced(tester);
    final tagged = remoteTasks().where((t) => t.tags.contains('chores'));
    expect(
      tagged.map((t) => t.title),
      unorderedEquals(['Call the dentist', 'Pick up bass strings']),
    );
  });

  testWidgets('removing a tag leaves the tasks', (tester) async {
    await app.pump(tester);
    await go(tester, '#pedals');
    await menu(tester, 'Tag options', 'Remove tag');
    expect(find.textContaining('It comes off 2 tasks'), findsOne);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(inSidebar('#pedals'), findsNothing);
    await synced(tester);
    final order = remoteTasks().singleWhere((t) => t.title == 'Order 1N914s');
    expect(order.tags, ['tayda']);
  });
}
