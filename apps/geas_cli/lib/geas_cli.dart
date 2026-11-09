/// The `geas` command line, with its I/O injected so it can be tested.
library;

import 'package:args/command_runner.dart';
import 'package:geas_core/geas_core.dart';

/// Opens a [GitHubClient] on [repo] with [token].
typedef Connect = GitHubClient Function(RepoRef repo, String token);

/// Returns the GitHub token, or null if there is none.
typedef ReadToken = String? Function();

/// Runs `geas` with [args] and returns the exit code.
Future<int> runGeas(
  List<String> args, {
  required Connect connect,
  required ReadToken readToken,
  required StringSink out,
  required StringSink err,
}) async {
  final runner = CommandRunner<int>(
      'geas', 'A task manager synced through GitHub.')
    ..addCommand(InitCommand(connect: connect, readToken: readToken, out: out));
  try {
    return await runner.run(args) ?? 0;
  } on UsageException catch (e) {
    err.writeln(e);
    return 64;
  } on GitHubException catch (e) {
    err.writeln('geas: ${e.message}${_hint(e.statusCode)}');
    return 1;
  } on UnsupportedFormatException catch (e) {
    err.writeln('geas: $e');
    return 1;
  } on FormatException catch (e) {
    err.writeln('geas: ${e.message}');
    return 1;
  }
}

String _hint(int statusCode) => switch (statusCode) {
      401 => '\nThe token was rejected. Check GEAS_TOKEN or create a new one.',
      403 => '\nThe token needs Contents read and write access to the repo.',
      _ => '',
    };

class InitCommand extends Command<int> {
  InitCommand({
    required Connect connect,
    required ReadToken readToken,
    required StringSink out,
  })  : _connect = connect,
        _readToken = readToken,
        _out = out;

  final Connect _connect;
  final ReadToken _readToken;
  final StringSink _out;

  @override
  final name = 'init';

  @override
  final description =
      'Set up a GitHub repo as the Geas data repo, writing geas.yaml if it '
      'has none. Safe to run again, and on every device.';

  @override
  String get invocation => 'geas init <owner/repo>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) usageException('Give the data repo as owner/repo.');
    final RepoRef repo;
    try {
      repo = RepoRef.parse(rest.single);
    } on FormatException catch (e) {
      usageException(e.message);
    }
    final token = _readToken();
    if (token == null || token.isEmpty) {
      usageException('No GitHub token. Set GEAS_TOKEN.');
    }

    final outcome = await initDataRepo(_connect(repo, token));
    _out.writeln(switch (outcome) {
      InitOutcome.created => 'Initialized $repo: wrote $repoConfigPath.',
      InitOutcome.alreadyInitialized =>
        '$repo is already a Geas data repo. Nothing to do.',
    });
    return 0;
  }
}
