import 'package:geas_core/geas_core.dart';

import 'command.dart';
import 'config.dart';
import 'token_stores.dart';

class InitCommand extends GeasCommand {
  InitCommand(super.context) {
    argParser.addOption('device',
        help: 'Name this device in sync commits (default: the hostname).');
  }

  @override
  final name = 'init';

  @override
  final description =
      'Set up a GitHub repo as the Geas data repo, writing geas.yaml if it '
      'has none, and make it this device\'s repo. Safe to run again, and on '
      'every device.';

  @override
  String get invocation => 'geas init [<owner/repo>] [--device <name>]';

  @override
  Future<int> run() async {
    if (rest.length > 1) usageException('Give the data repo as owner/repo.');
    final saved = await CliConfig.load(context.configDir);
    final RepoRef repo;
    if (rest.isEmpty) {
      if (saved == null) usageException('Give the data repo as owner/repo.');
      repo = saved.repo;
    } else {
      try {
        repo = RepoRef.parse(rest.single);
      } on FormatException catch (e) {
        usageException(e.message);
      }
    }

    // GEAS_TOKEN, then the stored token, then ask. Only an entered token
    // gets stored.
    var token = context.envToken ?? await context.tokens.read(repo);
    var entered = false;
    if (token == null || token.isEmpty) {
      token = context.promptToken();
      entered = true;
    }
    if (token == null || token.isEmpty) {
      usageException('No GitHub token. Set GEAS_TOKEN, or run this in a '
          'terminal to enter one.');
    }

    final outcome = await initDataRepo(context.connect(repo, token));
    out.writeln(switch (outcome) {
      InitOutcome.created => 'Initialized $repo: wrote $repoConfigPath.',
      InitOutcome.alreadyInitialized => '$repo is already a Geas data repo.',
    });

    final device = argResults!['device'] as String? ??
        (saved?.repo == repo ? saved!.device : context.hostname);
    await CliConfig(repo: repo, device: device).save(context.configDir);
    if (entered) {
      try {
        await context.tokens.write(repo, token);
        out.writeln('Stored the token.');
      } on TokenStoreException catch (e) {
        warn('$e Set GEAS_TOKEN to sync.');
      }
    }

    final session = await openSession();
    final result = await session.sync(token: token);
    await session.reload();
    final open = session.workspace.tasks.where((t) => !t.isCompleted).length;
    out.writeln('This device is "$device". Synced: $open open '
        '${open == 1 ? 'task' : 'tasks'}'
        '${result.pulled > 0 ? ', ${result.pulled} files pulled' : ''}.');
    return 0;
  }
}
