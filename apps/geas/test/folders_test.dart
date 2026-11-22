import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geas/features/shell/sidebar.dart';
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
  double top(Finder finder) => _topOf(finder);

  String remote(String path) => utf8.decode(app.github.files[path]!);

  Future<void> sync(WidgetTester tester) async {
    await tester.pump(syncDelay);
    await tester.pumpAndSettle();
  }

  Future<void> addFolder(WidgetTester tester, String name) async {
    await tester.tap(find.byTooltip('Add folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Folder name'), name);
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
  }

  /// Opens the list [name] and moves it with its menu.
  Future<void> moveList(WidgetTester tester, String name, String to) async {
    await tester.tap(inSidebar(name));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('List options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to folder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(to).last);
    await tester.pumpAndSettle();
  }

  testWidgets('a folder groups lists in the sidebar and collapses', (
    tester,
  ) async {
    await app.pump(tester);
    await addFolder(tester, 'Builds');
    expect(inSidebar('Builds'), findsOneWidget);
    expect(find.textContaining('Empty. Move a list'), findsOneWidget);

    await moveList(tester, 'Pedals', 'Builds');
    // Under its folder now, above the Lists heading; Home stays below it.
    expect(top(inSidebar('Builds')), lessThan(top(inSidebar('Pedals'))));
    expect(top(inSidebar('Pedals')), lessThan(top(inSidebar('Lists'))));
    expect(top(inSidebar('Lists')), lessThan(top(inSidebar('Home'))));
    expect(find.textContaining('Empty. Move a list'), findsNothing);

    await sync(tester);
    expect(Folder.parse(remote('folders/builds.yaml')).name, 'Builds');
    expect(TaskList.parse(remote('lists/pedals.yaml')).folder, 'builds');

    await tester.tap(inSidebar('Builds'));
    await tester.pumpAndSettle();
    expect(inSidebar('Pedals'), findsNothing);
    await tester.tap(inSidebar('Builds'));
    await tester.pumpAndSettle();
    expect(inSidebar('Pedals'), findsOneWidget);
  });

  testWidgets('a folder can be made while moving, and holds filters too', (
    tester,
  ) async {
    app.github.push({
      filterPath('errands'): utf8.encode(
        newFilter('Errands', '#errands', const []).encode(),
      ),
    });
    await app.pump(tester);
    expect(inSidebar('Filters'), findsOneWidget);
    await tester.tap(inSidebar('Errands'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filter options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to folder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New folder…'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Folder name'),
      'Out and about',
    );
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    // The only filter moved, so the Filters heading is gone.
    expect(inSidebar('Filters'), findsNothing);
    expect(
      top(inSidebar('Out and about')),
      lessThan(top(inSidebar('Errands'))),
    );
    await sync(tester);
    expect(
      SavedFilter.parse(remote('filters/errands.yaml')).folder,
      'out-and-about',
    );
  });

  testWidgets('trackers in a folder are grouped in Health', (tester) async {
    await app.pump(tester);
    await addFolder(tester, 'Diabetes');
    await tester.tap(inSidebar('Health'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CGM sensor'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to folder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Diabetes').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    final body = find.byType(ReorderableListView);
    Finder inBody(String text) =>
        find.descendant(of: body, matching: find.text(text));
    expect(top(inBody('Metformin')), lessThan(top(inBody('Diabetes'))));
    expect(top(inBody('Diabetes')), lessThan(top(inBody('CGM sensor'))));
    expect(inSidebar('1 in Health'), findsOneWidget);
    await sync(tester);
    expect(Tracker.parse(remote('trackers/cgm-sensor.md')).folder, 'diabetes');
  });

  testWidgets('renaming a folder, and deleting it frees what was in it', (
    tester,
  ) async {
    await app.pump(tester);
    await addFolder(tester, 'Builds');
    await moveList(tester, 'Pedals', 'Builds');

    await tester.tap(find.byTooltip('Builds folder options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename folder'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Folder name'),
      'Workbench',
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(inSidebar('Workbench'), findsOneWidget);

    await tester.tap(find.byTooltip('Workbench folder options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete folder'));
    await tester.pumpAndSettle();
    expect(find.textContaining('isn\'t deleted'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete folder'));
    await tester.pumpAndSettle();
    expect(inSidebar('Workbench'), findsNothing);
    expect(top(inSidebar('Lists')), lessThan(top(inSidebar('Pedals'))));

    await sync(tester);
    expect(app.github.files['folders/builds.yaml'], isNull);
    expect(TaskList.parse(remote('lists/pedals.yaml')).folder, isNull);
  });

  testWidgets('folders nest, reorder by dragging, and stay collapsed', (
    tester,
  ) async {
    // Tall enough that the whole sidebar is on screen.
    await app.pump(tester, size: const Size(1200, 1400));
    await addFolder(tester, 'Medical');
    await addFolder(tester, 'Diabetes');
    await addFolder(tester, 'Builds');
    await moveList(tester, 'Pedals', 'Diabetes');

    // Diabetes goes inside Medical; it can't go inside itself.
    await tester.tap(find.byTooltip('Diabetes folder options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move into folder'));
    await tester.pumpAndSettle();
    final dialog = find.byType(SimpleDialog);
    expect(
      find.descendant(of: dialog, matching: find.text('Diabetes')),
      findsNothing,
    );
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('Medical')),
    );
    await tester.pumpAndSettle();
    expect(top(inSidebar('Medical')), lessThan(top(inSidebar('Diabetes'))));
    expect(top(inSidebar('Diabetes')), lessThan(top(inSidebar('Pedals'))));
    expect(top(inSidebar('Pedals')), lessThan(top(inSidebar('Builds'))));
    expect(
      tester.getTopLeft(inSidebar('Diabetes')).dx,
      greaterThan(tester.getTopLeft(inSidebar('Medical')).dx),
    );
    await sync(tester);
    expect(Folder.parse(remote('folders/diabetes.yaml')).parent, 'medical');

    // Collapsing Medical hides everything inside it, and that's remembered.
    await tester.tap(inSidebar('Medical'));
    await tester.pumpAndSettle();
    expect(inSidebar('Diabetes'), findsNothing);
    expect(inSidebar('Pedals'), findsNothing);
    expect(app.config.config!.collapsedFolders, ['medical']);
    expect(app.config.config!.toJson()['collapsed_folders'], ['medical']);

    // Builds is dragged above Medical.
    await tester.tap(find.byTooltip('Builds folder options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reorder folders'));
    await tester.pumpAndSettle();
    final drag = await tester.startGesture(
      tester.getCenter(find.byTooltip('Drag Builds')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 8; i++) {
      await drag.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await drag.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(top(inSidebar('Builds')), lessThan(top(inSidebar('Medical'))));
    await sync(tester);
    expect(Folder.parse(remote('folders/builds.yaml')).order, 1);
    expect(Folder.parse(remote('folders/medical.yaml')).order, 2);
  });

  testWidgets('a folder closed last time starts closed', (tester) async {
    app.github.push({
      folderPath('builds'): utf8.encode(newFolder('Builds', const []).encode()),
      'lists/pedals.yaml': utf8.encode(
        const TaskList(
          id: 'pedals',
          name: 'Pedals',
          order: 1,
          folder: 'builds',
        ).encode(),
      ),
    });
    app.config.config = app.config.config!.copyWith(
      collapsedFolders: ['builds'],
    );
    await app.pump(tester);
    expect(inSidebar('Builds'), findsOneWidget);
    expect(inSidebar('Pedals'), findsNothing);
    await tester.tap(inSidebar('Builds'));
    await tester.pumpAndSettle();
    expect(inSidebar('Pedals'), findsOneWidget);
    expect(app.config.config!.collapsedFolders, isEmpty);
  });

  testWidgets('something filed in a folder that\'s gone shows as loose', (
    tester,
  ) async {
    app.github.push({
      'lists/pedals.yaml': utf8.encode(
        const TaskList(
          id: 'pedals',
          name: 'Pedals',
          order: 1,
          folder: 'deleted-elsewhere',
        ).encode(),
      ),
    });
    await app.pump(tester);
    expect(top(inSidebar('Lists')), lessThan(top(inSidebar('Pedals'))));
  });
}

double _topOf(Finder finder) =>
    TestWidgetsFlutterBinding.instance.renderViews.isEmpty
    ? 0
    : (finder.evaluate().single.renderObject! as RenderBox)
          .localToGlobal(Offset.zero)
          .dy;
