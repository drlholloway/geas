import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geas/main.dart';
import 'package:geas/state/store.dart';

// A Sunday noon, so the sample data's relative dates are stable.
final _now = DateTime(2026, 11, 8, 12);

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(1200, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [clockProvider.overrideWithValue(() => _now)],
      child: const GeasApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens on the inbox with the sidebar', (tester) async {
    await _pump(tester);
    expect(find.text('Geas'), findsOneWidget);
    expect(find.text('Inbox'), findsWidgets);
    expect(find.text('Call the dentist'), findsOneWidget);
    expect(find.text('Reply to the luthier'), findsOneWidget);
    expect(find.text('Order 1N914s'), findsNothing); // in Pedals
  });

  testWidgets('Today shows overdue and today across lists', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('Renew car registration'), findsOneWidget);
    expect(find.text('Order 1N914s'), findsOneWidget);
    expect(find.text('Clean the gutters'), findsNothing);
  });

  testWidgets('quick add puts a task in the current list', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'Buy flux');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Buy flux'), findsOneWidget);
  });

  testWidgets('checking a task moves it to Completed', (tester) async {
    await _pump(tester);
    final tile = find.ancestor(
      of: find.text('Reply to the luthier'),
      matching: find.byType(ListTile),
    );
    await tester.tap(
      find.descendant(of: tile, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Completed (1)'), findsOneWidget);
    expect(find.text('Reply to the luthier'), findsNothing); // collapsed
  });

  testWidgets('phone width puts the sidebar in a drawer', (tester) async {
    await _pump(tester, size: const Size(400, 800));
    expect(find.text('Next 7 days'), findsNothing);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next 7 days'));
    await tester.pumpAndSettle();
    expect(find.text('Pick up bass strings'), findsOneWidget);
  });
}
