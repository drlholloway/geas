import 'dart:convert';

import 'package:material_ui/material_ui.dart';
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

  Tracker? remote(String id) {
    final bytes = app.github.files[trackerPath(id)];
    return bytes == null ? null : Tracker.parse(utf8.decode(bytes));
  }

  Future<void> openHealth(WidgetTester tester) async {
    await app.pump(tester);
    await tester.tap(inSidebar('Health'));
    await tester.pumpAndSettle();
  }

  Future<void> sync(WidgetTester tester) async {
    await tester.pump(syncDelay);
    await tester.pumpAndSettle();
  }

  testWidgets('the Health view shows when and how often', (tester) async {
    await openHealth(tester);
    expect(find.text('Taken 3 h 55 min ago  ·  Today 08:05'), findsOneWidget);
    expect(
      find.text('1 today  ·  1.6 a day this week  ·  1.7 a day over 30 days'),
      findsOneWidget,
    );
    expect(find.text('Replaced 4.1 days ago  ·  Nov 4 09:05'), findsOneWidget);
    expect(
      find.text('Day 5 of 10  ·  lasts 9.7 days on average'),
      findsOneWidget,
    );
    expect(find.text('Next due Sat 09:05'), findsOneWidget);
    // A bar a day; the tooltips carry the counts.
    expect(find.byTooltip('Today: 1'), findsOneWidget);
    expect(find.byTooltip('Yesterday: 2'), findsOneWidget);
  });

  testWidgets('Take logs now, syncs, and can be undone', (tester) async {
    await openHealth(tester);
    final before = remote('metformin')!.entries.length;
    await tester.tap(find.widgetWithText(FilledButton, 'Take'));
    await tester.pump();
    expect(find.text('Taken 0 min ago  ·  Today 12:00'), findsOneWidget);
    expect(find.textContaining('2 today'), findsOneWidget);
    expect(find.text('Taken Metformin at Today 12:00'), findsOneWidget);
    await sync(tester);
    expect(remote('metformin')!.entries.length, before + 1);
    expect(remote('metformin')!.entries.last.at.toLocal(), now);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 today'), findsOneWidget);
    await sync(tester);
    expect(remote('metformin')!.entries.length, before);
  });

  testWidgets('tracking something new', (tester) async {
    await openHealth(tester);
    await tester.tap(find.byTooltip('Track something'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'metformin');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(find.text('"metformin" is already tracked.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Name'),
      'Infusion set',
    );
    await tester.tap(find.text('Sensor'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Replace every'),
      'often',
    );
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(find.text('Like 12h, 10d or 2w'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Replace every'),
      '3d',
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('Infusion set'), findsOneWidget);
    expect(find.text('Nothing logged yet'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Replace').last);
    await sync(tester);
    final tracker = remote('infusion-set')!;
    expect(tracker.kind, TrackerKind.sensor);
    expect(tracker.every, const Duration(days: 3));
    expect(tracker.entries.single.at.toLocal(), now);
  });

  testWidgets('a tracker\'s history, removing a time, and editing', (
    tester,
  ) async {
    await openHealth(tester);
    await tester.tap(find.text('CGM sensor'));
    await tester.pumpAndSettle();
    expect(
      find.text('Sensor  ·  every 10 days  ·  4 logged since Oct 6'),
      findsOneWidget,
    );
    expect(find.text('Last 90 days'), findsOneWidget);
    expect(find.text('Nov 4 09:05'), findsOneWidget);
    expect(find.text('10 days after the last'), findsNWidgets(2));
    expect(find.text('9 days after the last'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove Nov 4 09:05'));
    await tester.pumpAndSettle();
    expect(find.text('Nov 4 09:05'), findsNothing);
    expect(find.textContaining('Due since Nov 4'), findsOneWidget);
    // Overdue trackers are counted in the sidebar.
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Health'),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Dexcom');
    await tester.enterText(find.widgetWithText(TextField, 'Replace every'), '');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Dexcom'), findsOneWidget);
    await sync(tester);
    final tracker = remote('cgm-sensor')!;
    expect(tracker.name, 'Dexcom');
    expect(tracker.every, isNull);
    expect(tracker.entries, hasLength(3));
  });

  testWidgets('dragging a card by its handle reorders the list', (
    tester,
  ) async {
    await openHealth(tester);
    double top(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(top('Metformin'), lessThan(top('CGM sensor')));

    final drag = await tester.startGesture(
      tester.getCenter(find.byTooltip('Drag to reorder').first),
    );
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 11; i++) {
      await drag.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(top('CGM sensor'), lessThan(top('Metformin')));
    // The cards still open and log.
    expect(find.widgetWithText(FilledButton, 'Take'), findsOneWidget);
    await sync(tester);
    expect(remote('cgm-sensor')!.order, 1);
    expect(remote('metformin')!.order, 2);
    expect(remote('metformin')!.entries, isNotEmpty);
  });

  testWidgets('stop tracking deletes the log everywhere', (tester) async {
    await openHealth(tester);
    await tester.tap(find.text('Metformin'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop tracking'));
    await tester.pumpAndSettle();
    expect(find.textContaining('is deleted on every device'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Stop tracking'));
    await tester.pumpAndSettle();
    expect(find.text('Metformin'), findsNothing);
    expect(find.text('CGM sensor'), findsOneWidget);
    await sync(tester);
    expect(remote('metformin'), isNull);
  });

  testWidgets('with nothing tracked, a button adds the first', (tester) async {
    app.github.push({
      trackerPath('metformin'): null,
      trackerPath('cgm-sensor'): null,
    });
    await openHealth(tester);
    expect(find.textContaining('Nothing tracked yet.'), findsOneWidget);
    await tester.tap(find.text('Track something'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Vitamin D');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Vitamin D'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Take'), findsOneWidget);
  });

  testWidgets('the phone layout fits', (tester) async {
    await app.pump(tester, size: const Size(400, 860));
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(inSidebar('Health'));
    await tester.pumpAndSettle();
    expect(find.text('Metformin'), findsOneWidget);
    await tester.tap(find.text('Metformin'));
    await tester.pumpAndSettle();
    expect(find.text('Take now'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
