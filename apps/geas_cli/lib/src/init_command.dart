import 'package:geas_core/geas_core.dart';

import 'command.dart';
import 'config.dart';
import 'connect_repo.dart';

class InitCommand extends GeasCommand {
  InitCommand(super.context) {
    argParser.addOption('device',
        help: 'Name this device in sync commits (default: the hostname).');
  }

  @override
  final name = 'init';

  @override
  final description =
      'Use an existing repo and token: write geas.yaml if the repo has none '
      'and make it this device\'s repo. For scripts; `geas setup` walks you '
      'through everything.';

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
      usageException('No GitHub token. Set GEAS_TOKEN, or run `geas setup` '
          'in a terminal.');
    }

    await connectRepo(
      context,
      repo: repo,
      token: token,
      device: argResults!['device'] as String? ??
          (saved?.repo == repo ? saved!.device : context.hostname),
      store: entered,
    );
    return 0;
  }
}
