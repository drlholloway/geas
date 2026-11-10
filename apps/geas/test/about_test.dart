import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geas/features/settings/settings_screen.dart';

import 'harness.dart';

void main() {
  late TestApp app;
  setUp(() async {
    app = TestApp();
    await app.seed();
  });

  Future<void> openAbout(WidgetTester tester) async {
    await app.pump(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Source code'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Settings ends with the version, help and the tip jar', (
    tester,
  ) async {
    await openAbout(tester);
    expect(find.text('Geas 9.9.9'), findsOneWidget);

    await tester.tap(find.text('Help'));
    await tester.tap(find.text('Buy me a coffee'));
    await tester.tap(find.text('Source code'));
    expect(app.openedUrls.map((u) => '$u'), [helpUrl, tipUrl, sourceUrl]);
    expect(tipUrl, 'https://buymeacoffee.com/drlholloway');
  });
}
