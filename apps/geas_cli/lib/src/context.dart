import 'package:geas_core/geas_core.dart';

import 'token_stores.dart';

/// Opens a [GitHubClient] on [repo] with [token].
typedef Connect = GitHubClient Function(RepoRef repo, String token);

/// Everything `geas` touches outside itself, injected so it can be tested.
class GeasContext {
  GeasContext({
    required this.connect,
    required this.tokens,
    required this.promptToken,
    required this.editFile,
    required this.confirm,
    required this.ask,
    required this.openUrl,
    required this.run,
    required this.configDir,
    required this.dataDir,
    required this.hostname,
    required this.out,
    required this.err,
    this.envToken,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final Connect connect;

  /// Where `geas init` keeps the token: the Keychain or `secret-tool`.
  final TokenStore tokens;

  /// `GEAS_TOKEN`, which wins over [tokens] and is never stored.
  final String? envToken;

  /// Asks for a token without echoing it; null if there's no terminal.
  final String? Function() promptToken;

  /// Opens [path] in the user's editor; false if the editor failed.
  final Future<bool> Function(String path) editFile;

  /// Asks a yes-or-no question; false if there's no terminal.
  final bool Function(String question) confirm;

  /// Asks for a line of text, showing [prompt]; null if there's no terminal.
  final String? Function(String prompt) ask;

  /// Opens [url] in the browser; false if that failed.
  final Future<bool> Function(String url) openUrl;

  /// Runs other programs, such as `gh`.
  final RunProcess run;

  /// Holds `config.yaml`.
  final String configDir;

  /// Holds each data repo's local copy, under `<owner>/<repo>`.
  final String dataDir;

  /// The default device name for sync commits.
  final String hostname;

  final StringSink out;
  final StringSink err;
  final DateTime Function() clock;
}

/// A failure to report to the user as is, with exit code 1.
class CliException implements Exception {
  const CliException(this.message);

  final String message;

  @override
  String toString() => message;
}
