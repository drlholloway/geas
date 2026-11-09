import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geas/main.dart';
import 'package:geas/state/environment.dart';
import 'package:geas/state/store.dart';
import 'package:geas_core/geas_core.dart';
import 'package:geas_core/testing.dart';

import 'sample_data.dart';

const repo = RepoRef('drl', 'geas-data');
const goodToken = 'github_pat_good';

// A Sunday noon, so the sample data's relative dates are stable.
final now = DateTime(2026, 11, 8, 12);

/// The app wired to fakes: a GitHub repo, a token store, a config and a
/// local copy, all in memory.
class TestApp {
  final github = FakeGitHubClient(repo: repo);
  final tokens = MemoryTokenStore();
  final config = MemoryConfigStore();
  final local = MemoryStore();
  final openedUrls = <Uri>[];

  /// The client for a token other than [goodToken]; by default one that
  /// can't see the repo.
  GitHubClient Function(String token) otherToken = (_) =>
      FakeGitHubClient(repo: repo)..access = null;

  /// Every client is unreachable, as offline.
  var offline = false;

  AppEnvironment get environment => AppEnvironment(
    config: config,
    tokens: tokens,
    openStore: (_) => local,
    connect: (_, token) => offline
        ? UnreachableGitHub()
        : token == goodToken
        ? github
        : otherToken(token),
    openUrl: (url) async {
      openedUrls.add(url);
      return true;
    },
    hostname: 'testbox',
  );

  /// The repo initialized with the sample tasks, and this device set up
  /// for it.
  Future<void> seed({DateTime? tokenExpires}) async {
    await initDataRepo(github);
    final sample = sampleStore(now);
    github.push({
      for (final list in sample.lists)
        if (list.id != inboxId)
          'lists/${list.id}.yaml': utf8.encode(list.encode()),
      for (final task in sample.tasks)
        taskPath(task, now): utf8.encode(task.encode()),
    }, message: 'sample');
    tokens.tokens[repo] = goodToken;
    config.config = AppConfig(
      repo: repo,
      device: 'testbox',
      tokenExpires: tokenExpires,
    );
  }

  /// Task titles in the remote repo.
  List<String> remoteTitles() => [
    for (final MapEntry(:key, :value) in github.files.entries)
      if (key.endsWith('.md')) Task.parse(utf8.decode(value)).title,
  ];

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1200, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          environmentProvider.overrideWithValue(environment),
          clockProvider.overrideWithValue(() => now),
        ],
        child: const GeasApp(),
      ),
    );
    await tester.pumpAndSettle();
  }
}

/// A GitHub that never answers.
class UnreachableGitHub implements GitHubClient {
  @override
  Object? noSuchMethod(Invocation invocation) =>
      Future<Never>.error(const SocketException('Network is unreachable'));
}
