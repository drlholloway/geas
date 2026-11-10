import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geas/main.dart';
import 'package:geas/state/environment.dart';
import 'package:geas/state/home_widget.dart';
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
  TestApp({this.dataRepo = repo, this.hostname = 'testbox'});

  /// The data repo, and this device's name.
  final RepoRef dataRepo;
  final String hostname;

  late final github = FakeGitHubClient(repo: dataRepo);
  final tokens = MemoryTokenStore();
  final config = MemoryConfigStore();
  final local = MemoryStore();
  final openedUrls = <Uri>[];

  /// The client for a token other than [goodToken]; by default one that
  /// can't see the repo.
  late GitHubClient Function(String token) otherToken = (_) =>
      FakeGitHubClient(repo: dataRepo)..access = null;

  /// Every client is unreachable, as offline.
  var offline = false;

  /// The Android home-screen widget; none unless a test sets one.
  FakeHomeWidget? homeWidget;

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
    hostname: hostname,
    homeWidget: homeWidget,
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
    tokens.tokens[dataRepo] = goodToken;
    config.config = AppConfig(
      repo: dataRepo,
      device: hostname,
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

/// A home-screen widget that keeps what it's shown and takes taps from the
/// test.
class FakeHomeWidget implements HomeWidgetHost {
  /// Every snapshot shown, decoded, oldest first.
  final shown = <Map<String, Object?>>[];

  /// The link the app is launched with.
  Uri? launchLink;

  final _clicks = StreamController<Uri>.broadcast();

  /// Taps [link] on the widget.
  void tap(String link) => _clicks.add(Uri.parse(link));

  /// Task titles in [quadrant] of the latest snapshot.
  List<String> titlesIn(String quadrant) {
    final quadrants = (shown.last['quadrants']! as List)
        .cast<Map<String, Object?>>();
    final q = quadrants.singleWhere((q) => q['key'] == quadrant);
    return [
      for (final t in (q['tasks']! as List).cast<Map<String, Object?>>())
        t['title']! as String,
    ];
  }

  @override
  Future<void> show(String snapshot) async =>
      shown.add((jsonDecode(snapshot) as Map).cast());

  @override
  Future<Uri?> launchedFrom() async => launchLink;

  @override
  Stream<Uri> get clicks => _clicks.stream;
}
