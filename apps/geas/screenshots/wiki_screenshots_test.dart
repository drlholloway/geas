// Screenshots for the wiki, drawn by the real app against the fake GitHub
// and the sample tasks, so no one's own data ends up in them.
//
//   just screenshots              writes build/screenshots/*.png
//   GEAS_SHOTS=<dir> just screenshots
//
// Not part of `just test`: these only write pictures.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geas/features/shell/sidebar.dart';
import 'package:geas/main.dart';
import 'package:geas/state/environment.dart';
import 'package:geas/state/store.dart';
import 'package:geas_core/geas_core.dart';

import '../test/harness.dart';

const octocat = RepoRef('octocat', 'geas-data');
const desktop = Size(1200, 820);
const phone = Size(400, 860);
const _frame = Key('frame');

final outDir = Platform.environment['GEAS_SHOTS'] ?? 'build/screenshots';
final today = LocalDate.of(now);

void main() {
  setUpAll(_loadFonts);

  late TestApp app;
  setUp(
    () => app = TestApp(
      dataRepo: octocat,
      hostname: 'MacBook-Air',
      version: _pubspecVersion(),
    ),
  );

  Finder inSidebar(String text) =>
      find.descendant(of: find.byType(Sidebar), matching: find.text(text));

  Future<void> go(WidgetTester tester, String view) async {
    await tester.tap(inSidebar(view));
    await tester.pumpAndSettle();
  }

  /// Closes the task sheet by tapping the dimmed list above it.
  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(700, 40));
    await tester.pumpAndSettle();
  }

  shotTest('setup', (tester) async {
    await pump(tester, app, size: const Size(1000, 1100));
    await tester.enterText(
      find.widgetWithText(TextField, 'GitHub account'),
      'octocat',
    );
    await shot(tester, 'setup');
  });

  shotTest('tasks', (tester) async {
    await app.seed();
    pushOrders(app);
    await pump(tester, app);
    await shot(tester, 'inbox');

    await go(tester, 'Today');
    await shot(tester, 'today');

    await go(tester, 'Pedals');
    await tester.tap(find.byTooltip('List options'));
    await tester.pumpAndSettle();
    await shot(tester, 'list-menu');
    await tester.tapAt(const Offset(700, 400));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add list'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Garden');
    await shot(tester, 'new-list');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await go(tester, 'Pedals');
    await tester.tap(find.text('Order 1N914s'));
    await tester.pumpAndSettle();
    await shot(tester, 'task-sheet');
    await closeSheet(tester);
  });

  shotTest('matrix', (tester) async {
    await app.seed();
    await pump(tester, app);
    await go(tester, 'Matrix');
    await tester.tap(find.byTooltip('All four on one screen'));
    await tester.pumpAndSettle();
    await shot(tester, 'matrix-grid');
    await tester.tap(find.byTooltip('One quadrant at a time'));
    await tester.pumpAndSettle();
    await shot(tester, 'matrix-columns');
  });

  shotTest('orders', (tester) async {
    await app.seed();
    pushOrders(app);
    await pump(tester, app);
    await go(tester, 'Orders');
    await shot(tester, 'orders');

    await tester.tap(find.byTooltip('Add an order'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, "What's coming"),
      'Footswitches',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Vendor'), 'Tayda');
    await tester.enterText(
      find.widgetWithText(TextField, 'Order number'),
      'TE-2207815',
    );
    await tester.pump();
    await shot(tester, 'new-order');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fuzz enclosures'));
    await tester.pumpAndSettle();
    await shot(tester, 'order-sheet');
  });

  shotTest('conflicts', (tester) async {
    await app.seed();
    await pump(tester, app);
    // This device and another both retitle a task; this one is newer.
    final MapEntry(key: path, value: task) = [
      for (final MapEntry(:key, :value) in app.github.files.entries)
        if (key.endsWith('.md')) MapEntry(key, Task.parse(utf8.decode(value))),
    ].singleWhere((e) => e.value.title == 'Reply to the luthier');
    ProviderScope.containerOf(tester.element(find.byType(GeasApp)))
        .read(taskStoreProvider.notifier)
        .edit(task.id, (t) => t.copyWith(title: 'Reply to the luthier today'));
    app.github.push({
      path: utf8.encode(
        task
            .copyWith(
              title: 'Write to the luthier',
              updated: now.subtract(const Duration(hours: 1)),
            )
            .encode(),
      ),
    });
    await tester.tap(find.byTooltip('Sync now'));
    await tester.pumpAndSettle();
    await shot(tester, 'sync-conflict');

    await tester.tap(find.textContaining('Sync kept one side'));
    await tester.pumpAndSettle();
    await shot(tester, 'conflicts');
  });

  shotTest('settings', (tester) async {
    await app.seed(tokenExpires: now.add(const Duration(days: 9)));
    await pump(tester, app);
    await shot(tester, 'token-warning');
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await shot(tester, 'settings');
    await tester.scrollUntilVisible(
      find.text('Source code'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await shot(tester, 'about');
  });

  shotTest('phone', (tester) async {
    await app.seed();
    pushOrders(app);
    await pump(tester, app, size: phone);
    await shot(tester, 'phone-inbox');
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await shot(tester, 'phone-drawer');
    await go(tester, 'Matrix');
    await tester.tap(find.byTooltip('All four on one screen'));
    await tester.pumpAndSettle();
    await shot(tester, 'phone-matrix');
  });
}

/// The app's version from pubspec.yaml, without the build number.
String _pubspecVersion() {
  final line = File('pubspec.yaml')
      .readAsLinesSync()
      .firstWhere((l) => l.startsWith('version:'));
  return line.split(':').last.trim().split('+').first;
}

/// Orders in the fake repo: one on its way, arriving today; one ordered;
/// one delivered.
void pushOrders(TestApp app) {
  void push(Task task) =>
      app.github.push({taskPath(task, now): utf8.encode(task.encode())});
  Task order(String title, Order order, {String list = 'pedals'}) =>
      Task.create(
        title: title,
        now: now.subtract(const Duration(days: 2)),
      ).copyWith(list: list, order: order);

  push(
    order(
      'Fuzz enclosures',
      const Order(
        vendor: 'Tayda',
        number: 'TE-2207346',
      ).withPackage(Package.track('9400111899223397846185', eta: today)),
    ),
  );
  push(
    order('Pots and knobs', const Order(vendor: 'Small Bear', number: '58231')),
  );
  push(
    order(
      'Bass strings',
      const Order(
        vendor: 'StewMac',
        status: OrderStatus.delivered,
      ).withPackage(Package.track('1Z999AA10123456784')),
    ).complete(now.subtract(const Duration(days: 1))),
  );
}

/// A test that draws with shadows, as the app does.
void shotTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    debugDisableShadows = false;
    try {
      await body(tester);
    } finally {
      debugDisableShadows = true;
    }
  });
}

Future<void> pump(
  WidgetTester tester,
  TestApp app, {
  Size size = desktop,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _frame,
      child: ProviderScope(
        overrides: [
          environmentProvider.overrideWithValue(app.environment),
          clockProvider.overrideWithValue(() => now),
        ],
        child: const GeasApp(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Writes the whole window to `<outDir>/<name>.png`.
Future<void> shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  final element = find.byKey(_frame).evaluate().single;
  final bytes = await tester.runAsync(() async {
    final image = await captureImage(element);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  File('$outDir/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!);
}

/// Roboto and the Material icons from the Flutter SDK, so text and icons
/// draw as they do in the app instead of as test boxes.
Future<void> _loadFonts() async {
  var dir = File(Platform.resolvedExecutable).parent;
  while (!Directory('${dir.path}/artifacts/material_fonts').existsSync()) {
    if (dir.parent.path == dir.path) {
      throw StateError(
        'No material_fonts above ${Platform.resolvedExecutable}',
      );
    }
    dir = dir.parent;
  }
  final fonts = '${dir.path}/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      final data = File(file).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(data)));
    }
    await loader.load();
  }

  await load('Roboto', [
    for (final face in ['Regular', 'Medium', 'Bold', 'Italic', 'Light'])
      '$fonts/Roboto-$face.ttf',
  ]);
  await load('MaterialIcons', ['$fonts/MaterialIcons-Regular.otf']);
  const menlo = '/System/Library/Fonts/Menlo.ttc';
  if (File(menlo).existsSync()) await load('monospace', [menlo]);
}
