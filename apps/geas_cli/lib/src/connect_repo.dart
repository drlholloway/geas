import 'package:geas_core/geas_core.dart';

import 'config.dart';
import 'context.dart';
import 'output.dart';
import 'session.dart';
import 'token_stores.dart';

/// Checks that [token] can push to [repo], with advice when it can't.
Future<RepoAccess> checkToken(
    GeasContext context, RepoRef repo, String token) async {
  try {
    final access = await context.connect(repo, token).checkAccess();
    if (!access.canWrite) {
      throw CliException('The token can read $repo but not write to it. On '
          'GitHub, edit the token and set Contents to "Read and write".');
    }
    return access;
  } on GitHubException catch (e) {
    throw CliException(switch (e.statusCode) {
      401 => 'GitHub rejected the token. Copy it again, or create a new one.',
      404 => 'The token can\'t see $repo. Check the name, and on GitHub '
          'edit the token: under Repository access, choose "Only select '
          'repositories" and add $repo.',
      _ => describeError(e),
    });
  }
}

/// Makes [repo] this device's data repo: writes `geas.yaml` if it's missing,
/// saves the config, stores [token] if [store], and syncs.
Future<void> connectRepo(
  GeasContext context, {
  required RepoRef repo,
  required String token,
  required String device,
  required bool store,
}) async {
  final access = await checkToken(context, repo, token);
  final out = context.out;
  final outcome = await initDataRepo(context.connect(repo, token));
  out.writeln(switch (outcome) {
    InitOutcome.created => 'Initialized $repo: wrote $repoConfigPath.',
    InitOutcome.alreadyInitialized => '$repo is already a Geas data repo.',
  });

  var stored = false;
  if (store) {
    try {
      await context.tokens.write(repo, token);
      stored = true;
      out.writeln('Stored the token.');
    } on TokenStoreException catch (e) {
      context.err.writeln('geas: $e Set GEAS_TOKEN to sync.');
    }
  }
  final saved = await CliConfig.load(context.configDir);
  await CliConfig(
    repo: repo,
    device: device,
    // Remember when the stored token expires, to remind before it does.
    tokenExpires: stored
        ? access.tokenExpires
        : (saved?.repo == repo ? saved?.tokenExpires : null),
  ).save(context.configDir);

  final session = await Session.open(context, offline: false);
  final result = await session.sync(token: token);
  await session.reload();
  final open = session.workspace.tasks.where((t) => !t.isCompleted).length;
  out.writeln('This device is "$device". Synced: $open open '
      '${open == 1 ? 'task' : 'tasks'}'
      '${result.pulled > 0 ? ', ${result.pulled} files pulled' : ''}.');
  final expires = access.tokenExpires;
  if (stored && expires != null) {
    out.writeln(
        'The token expires ${formatDate(LocalDate.of(expires.toLocal()))}'
        '. Geas will remind you two weeks before; `geas setup` replaces it.');
  }
}
