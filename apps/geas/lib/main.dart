import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'features/setup/setup_screen.dart';
import 'features/shell/home_widget_driver.dart';
import 'features/shell/reminder_driver.dart';
import 'features/shell/sync_status.dart';
import 'state/desktop_background.dart';
import 'state/environment.dart';
import 'state/home_widget.dart';
import 'state/session.dart';

/// Held while a window is open, so a background start leaves syncing to it.
AppLock? appLock;

/// The longest a background start may take. Past this it gives up, so a
/// sync that can't finish (a Keychain prompt no one answers, a dead
/// network) doesn't leave a process behind each time the timer fires.
const backgroundSyncLimit = Duration(seconds: 90);

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final environment = await AppEnvironment.platform();
  final supportDir = environment.supportDir;
  if (args.contains(backgroundSyncFlag)) {
    // Started by the launch agent or systemd timer: sync and quit, with no
    // window.
    var code = 0;
    try {
      final run = await runDesktopBackgroundSync(
        environment,
        supportDir!,
      ).timeout(backgroundSyncLimit);
      debugPrint('geas: background sync: ${run.name}');
    } on Object catch (e) {
      debugPrint('geas: background sync failed: $e');
      code = 1;
    }
    exit(code);
  }
  if (supportDir != null && (Platform.isMacOS || Platform.isLinux)) {
    // A background sync may be finishing; give it a moment so the two
    // don't sync at once.
    for (var tries = 0; tries < 20 && appLock == null; tries++) {
      appLock = await AppLock.take(supportDir);
      if (appLock == null) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
  }
  if (Platform.isAndroid) {
    // Checkboxes on the home-screen widget run this in the background.
    await HomeWidget.registerInteractivityCallback(homeWidgetCallback);
  }
  runApp(
    ProviderScope(
      overrides: [environmentProvider.overrideWithValue(environment)],
      child: const GeasApp(),
    ),
  );
}

/// Setup until this device has a data repo, then the task screens.
class GeasApp extends ConsumerStatefulWidget {
  const GeasApp({super.key});

  @override
  ConsumerState<GeasApp> createState() => _GeasAppState();
}

class _GeasAppState extends ConsumerState<GeasApp> {
  final _router = createRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final light = buildTheme(Brightness.light);
    final dark = buildTheme(Brightness.dark);
    final config = ref.watch(configProvider);
    if (config case AsyncData(value: _?)) {
      return MaterialApp.router(
        title: 'Geas',
        debugShowCheckedModeBanner: false,
        theme: light,
        darkTheme: dark,
        routerConfig: _router,
        builder: (context, child) => HomeWidgetDriver(
          router: _router,
          child: ReminderDriver(child: SyncDriver(child: child!)),
        ),
      );
    }
    return MaterialApp(
      title: 'Geas',
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      // Blank while the config loads; setup without one.
      home: config.isLoading ? const Scaffold() : const SetupScreen(),
    );
  }
}
