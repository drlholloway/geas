import 'dart:io';

import 'package:geas_cli/geas_cli.dart';
import 'package:geas_core/geas_core.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final home = env['HOME'] ?? '.';
  // One client, closed at the end; an open keep-alive connection would hold
  // the process up for its idle timeout.
  final httpClient = http.Client();
  exitCode = await runGeas(
    args,
    GeasContext(
      connect: (repo, token) =>
          HttpGitHubClient(repo, token: token, httpClient: httpClient),
      tokens: platformTokenStore(),
      envToken: env['GEAS_TOKEN'],
      promptToken: _promptToken,
      editFile: _editFile,
      confirm: _confirm,
      ask: _ask,
      openUrl: _openUrl,
      run: runProcess,
      configDir:
          p.join(env['XDG_CONFIG_HOME'] ?? p.join(home, '.config'), 'geas'),
      dataDir: p.join(
          env['XDG_DATA_HOME'] ?? p.join(home, '.local', 'share'), 'geas'),
      hostname: Platform.localHostname.replaceFirst(RegExp(r'\.local$'), ''),
      out: stdout,
      err: stderr,
    ),
  );
  httpClient.close();
}

/// A hidden prompt when run interactively, otherwise null.
String? _promptToken() {
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

/// Runs `$VISUAL` or `$EDITOR` (default `vi`) through the shell, so values
/// like `code --wait` work.
Future<bool> _editFile(String path) async {
  final env = Platform.environment;
  final editor = [env['VISUAL'], env['EDITOR']]
      .firstWhere((e) => e != null && e.trim().isNotEmpty, orElse: () => 'vi')!;
  final process = await Process.start(
    '/bin/sh',
    ['-c', '$editor "\$1"', 'sh', path],
    mode: ProcessStartMode.inheritStdio,
  );
  return await process.exitCode == 0;
}

bool _confirm(String question) {
  if (!stdin.hasTerminal) return false;
  stdout.write('$question [Y/n] ');
  final answer = stdin.readLineSync()?.trim().toLowerCase() ?? 'n';
  return answer.isEmpty || answer.startsWith('y');
}

String? _ask(String prompt) {
  if (!stdin.hasTerminal) return null;
  stdout.write(prompt);
  final line = stdin.readLineSync();
  if (line == null) stdout.writeln();
  return line?.trim();
}

/// `open` on macOS, `xdg-open` on Linux.
Future<bool> _openUrl(String url) async {
  final opener = Platform.isMacOS ? 'open' : 'xdg-open';
  try {
    return (await Process.run(opener, [url])).exitCode == 0;
  } on ProcessException {
    return false;
  }
}
