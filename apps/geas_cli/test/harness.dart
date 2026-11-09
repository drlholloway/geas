import 'dart:convert';
import 'dart:io';

import 'package:geas_cli/geas_cli.dart';
import 'package:geas_core/geas_core.dart';
import 'package:geas_core/testing.dart';
import 'package:path/path.dart' as p;

const repo = RepoRef('drl', 'geas-data');

/// Runs `geas` against an in-memory GitHub and a temporary home.
class Harness {
  Harness(this.root);

  static Future<Harness> create() async =>
      Harness(await Directory.systemTemp.createTemp('geas-cli-test-'));

  final Directory root;
  final github = FakeGitHubClient(repo: repo);
  final tokens = MemoryTokenStore();

  /// What the prompt returns; null means no terminal.
  String? typedToken = 'typed_token';
  String? envToken;

  /// Replaces [github] for every connection when set.
  GitHubClient? client;

  /// The tokens each connection was opened with.
  final connections = <String>[];

  /// Runs on each connection, before it's returned.
  void Function(String token)? onConnect;

  /// Monday, November 9, 2026, at noon here.
  DateTime now = DateTime(2026, 11, 9, 12);

  Future<bool> Function(String path) editor = (_) async => true;
  bool confirmAnswer = false;

  /// Answers to [GeasContext.ask], in order; null once they run out.
  final answers = <String>[];

  /// Answers to the hidden token prompt after [typedToken], in order.
  final moreTokens = <String>[];

  /// Every prompt shown by ask and confirm.
  final prompts = <String>[];
  final openedUrls = <String>[];

  /// Handles `gh` and other programs; by default there's no `gh`.
  Future<ProcessResult> Function(String exe, List<String> args) programs =
      (exe, args) async => throw ProcessException(exe, args, 'not found', 2);

  final out = StringBuffer();
  final err = StringBuffer();

  String get configDir => p.join(root.path, 'config');
  String get dataDir => p.join(root.path, 'data');

  /// Runs `geas` with [args] after clearing [out] and [err].
  Future<int> call(List<String> args) {
    out.clear();
    err.clear();
    return runGeas(
      args,
      GeasContext(
        connect: (r, token) {
          connections.add(token);
          onConnect?.call(token);
          return client ?? github;
        },
        tokens: tokens,
        envToken: envToken,
        promptToken: () {
          final token = typedToken;
          typedToken = moreTokens.isEmpty ? null : moreTokens.removeAt(0);
          return token;
        },
        editFile: (path) => editor(path),
        confirm: (question) {
          prompts.add(question);
          return confirmAnswer;
        },
        ask: (prompt) {
          prompts.add(prompt);
          return answers.isEmpty ? null : answers.removeAt(0);
        },
        openUrl: (url) async {
          openedUrls.add(url);
          return true;
        },
        run: (exe, args, {stdin}) => programs(exe, args),
        configDir: configDir,
        dataDir: dataDir,
        hostname: 'testbox',
        out: out,
        err: err,
        clock: () => now,
      ),
    );
  }

  /// `geas init drl/geas-data` on an empty repo, then clears the output.
  Future<void> init() async {
    final code = await this(['init', '$repo']);
    if (code != 0) throw StateError('init failed: $err');
  }

  /// The text of the file at [path] on GitHub, or null.
  String? remote(String path) {
    final bytes = github.files[path];
    return bytes == null ? null : utf8.decode(bytes);
  }

  /// The task on GitHub whose title is [title].
  Task remoteTask(String title) => github.files.entries
      .where((e) => e.key.endsWith('.md'))
      .map((e) => Task.parse(utf8.decode(e.value)))
      .singleWhere((t) => t.title == title);

  /// Pushes a task from "another device".
  void pushTask(String id, String title, {String extra = ''}) => github.push({
        'tasks/$id.md': utf8.encode('---\n'
            'id: $id\n'
            'title: $title\n'
            '$extra'
            'created: 2026-11-01T10:00:00Z\n'
            'updated: 2026-11-01T10:00:00Z\n'
            '---\n'),
      }, message: 'other device');

  Future<void> dispose() => root.delete(recursive: true);
}

/// A [GitHubClient] that can't reach the network.
class UnreachableGitHub implements GitHubClient {
  @override
  Object? noSuchMethod(Invocation invocation) =>
      Future<Never>.error(const SocketException('Network is unreachable'));
}
