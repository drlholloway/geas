// The app on the sample tasks, for trying it on an emulator without a
// GitHub account: the real local copy and widget, but a GitHub that lives
// in memory, seeded with test/sample_data.dart.
//
//   cd apps/geas && flutter run -t demo/main.dart
//
// Not shipped. The home-screen widget's background work uses the real
// environment, so ticking a task there with the app closed finishes it in
// the local copy but can't sync it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas/main.dart';
import 'package:geas/state/environment.dart';
import 'package:geas/state/home_widget.dart';
import 'package:geas_core/geas_core.dart';
import 'package:geas_core/testing.dart';
import 'package:home_widget/home_widget.dart';

import '../test/sample_data.dart';

const _repo = RepoRef('octocat', 'geas-data');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final real = await AppEnvironment.platform();
  if (Platform.isAndroid) {
    await HomeWidget.registerInteractivityCallback(homeWidgetCallback);
  }

  final now = DateTime.now();
  final github = FakeGitHubClient(repo: _repo);
  await initDataRepo(github);
  // The fake GitHub forgets everything when the app stops, so start it
  // from this device's copy if there is one, else from the samples.
  final copy = await real.openStore(_repo).working.readAll();
  if (copy.keys.any((path) => path.startsWith('tasks/'))) {
    github.push(copy, message: 'this device');
  } else {
    final sample = sampleStore(now);
    github.push({
      for (final list in sample.lists)
        if (list.id != inboxId)
          'lists/${list.id}.yaml': utf8.encode(list.encode()),
      for (final task in sample.tasks)
        taskPath(task, now): utf8.encode(task.encode()),
    }, message: 'sample');
  }
  await real.config.save(const AppConfig(repo: _repo, device: 'emulator'));

  final tokens = MemoryTokenStore()..tokens[_repo] = 'demo';
  runApp(
    ProviderScope(
      overrides: [
        environmentProvider.overrideWithValue(
          AppEnvironment(
            config: real.config,
            tokens: tokens,
            openStore: real.openStore,
            connect: (_, _) => github,
            openUrl: real.openUrl,
            hostname: 'emulator',
            homeWidget: real.homeWidget,
          ),
        ),
      ],
      child: const GeasApp(),
    ),
  );
}
