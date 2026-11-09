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
    return await checkTokenAccess(context.connect(repo, token));
  } on TokenProblem catch (e) {
    throw CliException(e.message);
  } on GitHubException catch (e) {
    throw CliException(describeError(e));
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
