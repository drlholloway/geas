import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';

void main() => runApp(const ProviderScope(child: GeasApp()));

class GeasApp extends StatefulWidget {
  const GeasApp({super.key});

  @override
  State<GeasApp> createState() => _GeasAppState();
}

class _GeasAppState extends State<GeasApp> {
  final _router = createRouter();

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Geas',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    routerConfig: _router,
  );
}
