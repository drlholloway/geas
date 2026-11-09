import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'features/setup/setup_screen.dart';
import 'features/shell/sync_status.dart';
import 'state/environment.dart';
import 'state/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final environment = await AppEnvironment.platform();
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
        builder: (context, child) => SyncDriver(child: child!),
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
