import 'dart:io';

import 'package:geas_cli/geas_cli.dart';
import 'package:geas_core/geas_core.dart';

Future<void> main(List<String> args) async {
  exitCode = await runGeas(
    args,
    connect: (repo, token) => HttpGitHubClient(repo, token: token),
    readToken: _readToken,
    out: stdout,
    err: stderr,
  );
}

/// `GEAS_TOKEN`, otherwise a hidden prompt when run interactively.
String? _readToken() {
  final fromEnv = Platform.environment['GEAS_TOKEN'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  if (!stdin.hasTerminal) return null;
  try {
    stdin.echoMode = false;
  } on StdinException {
    // Not a real terminal (e.g. /dev/null); never read a token visibly.
    return null;
  }

  stdout.write('GitHub token: ');
  try {
    return stdin.readLineSync()?.trim();
  } finally {
    stdin.echoMode = true;
    stdout.writeln();
  }
}
