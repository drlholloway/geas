import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geas/state/sync.dart';
import 'package:geas_core/geas_core.dart';

import 'harness.dart';

void main() {
  late TestApp app;
  setUp(() async {
    app = TestApp();
    await app.seed();
  });

  Finder quadrant(Quadrant q) => find.byKey(ValueKey('quadrant-${q.name}'));
  Finder inQuadrant(Quadrant q, String text) =>
      find.descendant(of: quadrant(q), matching: find.text(text));

  Future<void> openMatrix(WidgetTester tester, {Size? size}) async {
    await app.pump(tester, size: size ?? const Size(1200, 900));
    if (size != null) {
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Matrix'));
    await tester.pumpAndSettle();
  }

  testWidgets('each quadrant holds one priority', (tester) async {
    await openMatrix(tester);
    expect(inQuadrant(Quadrant.doFirst, 'Order 1N914s'), findsOneWidget);
    expect(inQuadrant(Quadrant.schedule, 'Renew car registration'), findsOne);
    expect(
      inQuadrant(Quadrant.schedule, 'Draft the Geas sync design'),
      findsOne,
    );
    expect(inQuadrant(Quadrant.delegate, 'Reply to the luthier'), findsOne);
    expect(inQuadrant(Quadrant.drop, 'Call the dentist'), findsOneWidget);
    expect(find.text('Solder the fuzz board'), findsNothing); // done
  });

  testWidgets('dragging a task to another quadrant sets its priority', (
    tester,
  ) async {
    await openMatrix(tester);
    final from = tester.getCenter(
      inQuadrant(Quadrant.delegate, 'Reply to the luthier'),
    );
    final to = tester.getCenter(quadrant(Quadrant.doFirst));
    final gesture = await tester.startGesture(from);
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(inQuadrant(Quadrant.doFirst, 'Reply to the luthier'), findsOne);
    expect(inQuadrant(Quadrant.delegate, 'Reply to the luthier'), findsNothing);

    await tester.pump(syncDelay);
    await tester.pumpAndSettle();
    final task = [
      for (final MapEntry(:key, :value) in app.github.files.entries)
        if (key.endsWith('.md')) Task.parse(utf8.decode(value)),
    ].singleWhere((t) => t.title == 'Reply to the luthier');
    expect(task.priority, Priority.high);
  });

  testWidgets('filters by tag and leaves out undated tasks', (tester) async {
    await openMatrix(tester);
    await tester.tap(find.text('Undated'));
    await tester.pumpAndSettle();
    expect(find.text('Reply to the luthier'), findsNothing);
    expect(find.text('Order 1N914s'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tag-filter')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(MenuItemButton, '#errands').hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(find.text('Order 1N914s'), findsNothing);
    expect(inQuadrant(Quadrant.drop, 'Call the dentist'), findsOneWidget);
    expect(inQuadrant(Quadrant.drop, 'Pick up bass strings'), findsOneWidget);
  });

  testWidgets('on a phone the quadrants are tabs', (tester) async {
    await openMatrix(tester, size: const Size(400, 800));
    expect(find.text('Do 1'), findsOneWidget);
    expect(find.text('Order 1N914s'), findsOneWidget);
    await tester.tap(find.text('Delegate 1'));
    await tester.pumpAndSettle();
    expect(find.text('Reply to the luthier'), findsOneWidget);
  });

  testWidgets('the switch shows all four on a phone', (tester) async {
    await openMatrix(tester, size: const Size(400, 800));
    expect(find.text('Do 1'), findsOneWidget); // tabs at first
    await tester.tap(find.byTooltip('All four on one screen'));
    await tester.pumpAndSettle();
    expect(find.text('Do 1'), findsNothing);
    for (final q in Quadrant.values) {
      expect(quadrant(q), findsOneWidget);
    }
    expect(inQuadrant(Quadrant.doFirst, 'Order 1N914s'), findsOneWidget);
    expect(inQuadrant(Quadrant.delegate, 'Reply to the luthier'), findsOne);
  });

  testWidgets('four boxes on a phone keep their whole titles', (tester) async {
    await openMatrix(tester, size: const Size(400, 800));
    await tester.tap(find.byTooltip('All four on one screen'));
    await tester.pumpAndSettle();
    for (final q in Quadrant.values) {
      final title = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: inQuadrant(q, q.title),
          matching: find.byType(RichText),
        ),
      );
      expect(
        title.size.width,
        greaterThanOrEqualTo(title.getMaxIntrinsicWidth(double.infinity)),
        reason: '${q.title} is cut short',
      );
    }
  });

  testWidgets('and one at a time on a wide screen', (tester) async {
    await openMatrix(tester);
    expect(quadrant(Quadrant.drop), findsOneWidget);
    await tester.tap(find.byTooltip('One quadrant at a time'));
    await tester.pumpAndSettle();
    expect(find.text('Do 1'), findsOneWidget);
    expect(quadrant(Quadrant.drop), findsNothing);
  });
}
