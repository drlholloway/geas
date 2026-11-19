import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geas/features/shell/sidebar.dart';
import 'package:geas/features/tasks/task_tile.dart';
import 'package:geas/state/sync.dart';
import 'package:geas_core/geas_core.dart';
import 'package:material_ui/material_ui.dart';

import 'harness.dart';

void main() {
  late TestApp app;
  setUp(() async {
    app = TestApp();
    await app.seed();
  });

  Finder inSidebar(String text) =>
      find.descendant(of: find.byType(Sidebar), matching: find.text(text));

  Future<void> openSearch(WidgetTester tester) async {
    await app.pump(tester);
    await tester.tap(inSidebar('Search'));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String query) async {
    await tester.enterText(
      find.widgetWithText(TextField, 'Search tasks'),
      query,
    );
    await tester.pumpAndSettle();
  }

  List<String> results(WidgetTester tester) => [
    for (final tile in tester.widgetList<TaskTile>(find.byType(TaskTile)))
      tile.task.title,
  ];

  testWidgets('search finds tasks as you type', (tester) async {
    await openSearch(tester);
    expect(find.byType(TaskTile), findsNothing);

    await type(tester, 'LUTHIER');
    expect(find.text('1 task'), findsOneWidget);
    // In the notes, not the title.
    await type(tester, 'three-way');
    expect(results(tester), ['Draft the Geas sync design']);
    await type(tester, 'the #errands');
    expect(results(tester), ['Call the dentist']);
    await type(tester, '^pedals is:all');
    expect(results(tester), [
      'Order 1N914s',
      'Pick up bass strings',
      'Solder the fuzz board',
    ]);
    await type(tester, 'due:overdue');
    expect(results(tester), ['Renew car registration']);
    await type(tester, 'zebra');
    expect(find.text('No tasks match.'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskTile), findsNothing);
    expect(find.byTooltip('Save as a filter'), findsNothing);
  });

  testWidgets('a search saved as a filter lives in the sidebar', (
    tester,
  ) async {
    await openSearch(tester);
    await type(tester, '#errands');
    await tester.tap(find.byTooltip('Save as a filter'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Errands');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Errands'), findsOneWidget);
    expect(inSidebar('Filters'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Errands'),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(results(tester), ['Call the dentist', 'Pick up bass strings']);

    await tester.pump(syncDelay);
    await tester.pumpAndSettle();
    final remote = SavedFilter.parse(
      utf8.decode(app.github.files['filters/errands.yaml']!),
    );
    expect(remote.query, '#errands');

    // Open it from another view, change it, and update it.
    await tester.tap(inSidebar('Inbox'));
    await tester.pumpAndSettle();
    await tester.tap(inSidebar('Errands'));
    await tester.pumpAndSettle();
    expect(results(tester), ['Call the dentist', 'Pick up bass strings']);
    await type(tester, '#errands ^pedals');
    expect(results(tester), ['Pick up bass strings']);
    await tester.tap(find.text('Update filter'));
    await tester.pumpAndSettle();
    expect(find.text('Update filter'), findsNothing);
    await tester.pump(syncDelay);
    await tester.pumpAndSettle();
    expect(
      SavedFilter.parse(utf8.decode(app.github.files['filters/errands.yaml']!))
          .query,
      '#errands ^pedals',
    );

    await tester.tap(find.byTooltip('Filter options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete filter'));
    await tester.pumpAndSettle();
    expect(inSidebar('Errands'), findsNothing);
    expect(find.widgetWithText(AppBar, 'Search'), findsOneWidget);
    await tester.pump(syncDelay);
    await tester.pumpAndSettle();
    expect(app.github.files['filters/errands.yaml'], isNull);
  });
}
