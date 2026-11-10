import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geas/features/shell/sidebar.dart';
import 'package:geas/state/sync.dart';
import 'package:geas_core/geas_core.dart';

import 'harness.dart';

void main() {
  late TestApp app;
  final today = LocalDate.of(now);

  /// Pushes a task with [order] to the remote, as another device would.
  void pushOrder(String title, Order order, {bool done = false}) {
    var task = Task.create(title: title, now: now).copyWith(order: order);
    if (done) task = task.complete(now);
    app.github.push({taskPath(task, now): utf8.encode(task.encode())});
  }

  Task remote(String title) => [
    for (final MapEntry(:key, :value) in app.github.files.entries)
      if (key.endsWith('.md')) Task.parse(utf8.decode(value)),
  ].singleWhere((t) => t.title == title);

  setUp(() async {
    app = TestApp();
    await app.seed();
  });

  Finder inSidebar(String text) =>
      find.descendant(of: find.byType(Sidebar), matching: find.text(text));

  Future<void> openOrders(WidgetTester tester) async {
    await app.pump(tester);
    await tester.tap(inSidebar('Orders'));
    await tester.pumpAndSettle();
  }

  testWidgets('the Orders view groups by status', (tester) async {
    pushOrder('Order diodes', const Order(vendor: 'Tayda', number: 'TE-1'));
    pushOrder(
      'Order knobs',
      const Order().withPackage(
        Package.track('123456789012', eta: today.addDays(1)),
      ),
    );
    pushOrder(
      'Order enclosure',
      const Order(status: OrderStatus.delivered),
      done: true,
    );
    await openOrders(tester);
    expect(
      find.descendant(of: find.byType(Sidebar), matching: find.text('2')),
      findsWidgets,
    );
    expect(find.text('Ordered  1'), findsOneWidget);
    expect(find.text('Tayda  #TE-1'), findsOneWidget);
    expect(find.text('Shipped  1'), findsOneWidget);
    expect(find.text('FedEx 123456789012  ·  ETA Tomorrow'), findsOneWidget);
    expect(find.text('Delivered  1'), findsOneWidget);
    expect(find.text('Order enclosure'), findsNothing); // collapsed

    await tester.tap(find.byTooltip('Track 123456789012'));
    expect(app.openedUrls.single.host, 'www.fedex.com');
  });

  testWidgets('tracking an order from the task sheet', (tester) async {
    await app.pump(tester);
    await tester.tap(find.text('Reply to the luthier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Track an order'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Vendor'), 'StewMac');
    await tester.enterText(
      find.widgetWithText(TextField, 'Paste a tracking number'),
      '1Z999AA10123456784',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('UPS 1Z999AA10123456784'), findsOneWidget);
    expect(find.text('Shipped'), findsOneWidget);

    await tester.pump(syncDelay);
    await tester.pumpAndSettle();
    final order = remote('Reply to the luthier').order!;
    expect(order.vendor, 'StewMac');
    expect(order.status, OrderStatus.shipped);
    expect(order.packages.single.carrier, Carrier.ups);
  });

  testWidgets('a delivered order offers to finish the task', (tester) async {
    pushOrder('Order pots', const Order(status: OrderStatus.shipped));
    await app.pump(tester);
    await tester.tap(find.text('Order pots'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Order status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delivered').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark done'));
    await tester.pumpAndSettle();
    expect(find.text('Mark done'), findsNothing);
    await tester.pump(syncDelay);
    await tester.pumpAndSettle();
    final task = remote('Order pots');
    expect(task.isCompleted, isTrue);
    expect(task.order!.status, OrderStatus.delivered);
  });

  testWidgets('a package due today shows on its row and in Today', (
    tester,
  ) async {
    pushOrder(
      'Order strings',
      const Order().withPackage(Package.track('123456789012', eta: today)),
    );
    await app.pump(tester);
    expect(find.text('Arrives Today'), findsOneWidget);
    await tester.tap(inSidebar('Today'));
    await tester.pumpAndSettle();
    expect(find.text('Packages arriving  1'), findsOneWidget);
    expect(find.text('Order strings'), findsOneWidget);
  });

  testWidgets('with no orders, a button adds the first', (tester) async {
    await openOrders(tester);
    expect(find.text('No orders yet.'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(find.text('Add an order'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Vendor'), 'Tayda');
    await tester.enterText(
      find.widgetWithText(TextField, 'Tracking number'),
      '9400111899223397846185',
    );
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    // The new task opens.
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('USPS 9400111899223397846185'),
      ),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(700, 40));
    await tester.pumpAndSettle();
    expect(find.text('Shipped  1'), findsOneWidget);
    expect(find.text('Order from Tayda'), findsOneWidget);
    await tester.pump(syncDelay);
    await tester.pumpAndSettle();
    final order = remote('Order from Tayda').order!;
    expect(order.vendor, 'Tayda');
    expect(order.packages.single.carrier, Carrier.usps);
  });

  testWidgets('with orders, a + button adds another', (tester) async {
    pushOrder('Order diodes', const Order(vendor: 'Tayda'));
    await openOrders(tester);
    await tester.tap(find.byTooltip('Add an order'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Add'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'))
          .onPressed,
      isNull, // nothing typed yet
    );
    await tester.enterText(
      find.widgetWithText(TextField, "What's coming"),
      'Order knobs',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Order number'),
      '42',
    );
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(700, 40));
    await tester.pumpAndSettle();
    expect(find.text('Ordered  2'), findsOneWidget);
    expect(find.text('#42'), findsOneWidget);
  });
}
