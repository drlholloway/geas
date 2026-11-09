import 'dart:io';

import 'package:geas_core/geas_core.dart';

import 'command.dart';
import 'config.dart';
import 'connect_repo.dart';
import 'context.dart';
import 'output.dart';

class SetupCommand extends GeasCommand {
  SetupCommand(super.context);

  @override
  final name = 'setup';

  @override
  final description = 'Walk through everything Geas needs: a private data '
      'repo, a token that can reach only that repo, and this device. Run it '
      'again to replace an expiring token or to set up another device.';

  @override
  String get invocation => 'geas setup';

  @override
  Future<int> run() async {
    if (rest.isNotEmpty) usageException('setup takes no arguments.');
    final saved = await CliConfig.load(context.configDir);
    out.writeln('Geas keeps your tasks in a private GitHub repo, and each '
        'device syncs\nwith its own token that can reach only that repo.\n');

    out.writeln('Step 1 of 3: this device');
    final device =
        _ask('Name for this device', saved?.device ?? context.hostname);

    out.writeln('\nStep 2 of 3: the data repo');
    final ghLogin = await _ghLogin();
    final owner =
        _ask('GitHub account that owns it', saved?.repo.owner ?? ghLogin);
    final repoName = _ask('Repo name', saved?.repo.name ?? 'geas-data');
    final RepoRef repo;
    try {
      repo = RepoRef.parse('$owner/$repoName');
    } on FormatException catch (e) {
      throw CliException(e.message);
    }
    await _ensureRepo(repo, withGh: ghLogin != null);

    out.writeln('\nStep 3 of 3: a token for this device');
    final (token, isNew) = await _token(repo, device);
    await connectRepo(context,
        repo: repo, token: token, device: device, store: isNew);
    if (isNew && saved?.repo == repo && saved?.tokenExpires != null) {
      out.writeln('Delete this device\'s old token at '
          'https://github.com/settings/personal-access-tokens once you\'re '
          'done with it.');
    }
    return 0;
  }

  /// Asks for [label], offering [fallback] for an empty answer.
  String _ask(String label, String? fallback) {
    while (true) {
      final answer =
          context.ask(fallback == null ? '$label: ' : '$label [$fallback]: ');
      if (answer == null) throw const CliException(_needsTerminal);
      if (answer.trim().isNotEmpty) return answer.trim();
      if (fallback != null) return fallback;
    }
  }

  /// The account `gh` is logged in to, or null without `gh`.
  Future<String?> _ghLogin() async {
    try {
      final result = await context.run('gh', ['api', 'user', '--jq', '.login']);
      final login = (result.stdout as String).trim();
      return result.exitCode == 0 && login.isNotEmpty ? login : null;
    } on ProcessException {
      return null;
    }
  }

  /// Makes sure [repo] exists and is private: with `gh` if it's there,
  /// otherwise through a filled-in form on GitHub.
  Future<void> _ensureRepo(RepoRef repo, {required bool withGh}) async {
    if (withGh) {
      final view = await context.run('gh', [
        'repo',
        'view',
        '$repo',
        '--json',
        'visibility',
        '--jq',
        '.visibility'
      ]);
      if (view.exitCode == 0) {
        final visibility = (view.stdout as String).trim();
        if (visibility == 'PRIVATE') {
          out.writeln('Found $repo, and it\'s private.');
          return;
        }
        warn('$repo is ${visibility.toLowerCase()}: anyone who can see it '
            'can read your tasks.');
        if (!context.confirm('Use it anyway?')) {
          throw CliException('Make $repo private on GitHub, or pick another '
              'name, and run `geas setup` again.');
        }
        return;
      }
      if (context.confirm('Create the private repo $repo with gh?')) {
        final create = await context.run('gh', [
          'repo', 'create', '$repo', '--private', //
          '--description', dataRepoDescription,
        ]);
        if (create.exitCode == 0) {
          out.writeln('Created $repo.');
          return;
        }
        warn('gh couldn\'t create it: ${(create.stderr as String).trim()}');
      }
    }

    out.writeln('Create the repo on GitHub. The form is filled in: check it '
        'says Private,\nthen click "Create repository". If it already '
        'exists, skip this.');
    await _open(newRepoUrl(repo));
    if (context.ask('Press Enter when $repo exists. ') == null) {
      throw const CliException(_needsTerminal);
    }
  }

  /// A token that can push to [repo], and whether it's a new one. Offers to
  /// keep a stored token that still works.
  Future<(String, bool)> _token(RepoRef repo, String device) async {
    final stored = await context.tokens.read(repo);
    if (stored != null) {
      try {
        final access = await checkToken(context, repo, stored);
        final expires = access.tokenExpires;
        out.writeln('This device already has a working token for $repo'
            '${expires == null ? '' : ' (it expires ${_date(expires)})'}.');
        if (!context.confirm('Make a new one anyway?')) return (stored, false);
      } on CliException {
        out.writeln('The token stored for $repo no longer works.');
      }
    }

    out.writeln('GitHub will open a token form with the name, a one-year '
        'expiry and the\npermission (Contents: read and write) filled in. '
        'GitHub can\'t pre-select\nthe repo, so:\n'
        '  1. Under "Repository access", choose "Only select repositories" '
        'and pick $repo.\n'
        '  2. Click "Generate token" and copy it.');
    await _open(newTokenUrl(repo, device, LocalDate.of(context.clock())));
    while (true) {
      final token = context.promptToken()?.trim();
      if (token == null) throw const CliException(_needsTerminal);
      if (token.isEmpty) {
        throw const CliException(
            'No token entered. Run `geas setup` again when you have one.');
      }
      if (token.startsWith('ghp_')) {
        warn('That\'s a classic token, which can reach every repo you can. '
            'A fine-grained token limited to $repo is safer.');
        if (!context.confirm('Use it anyway?')) continue;
      }
      try {
        await checkToken(context, repo, token);
        return (token, true);
      } on CliException catch (e) {
        warn(e.message);
        out.writeln('Fix it on GitHub and paste the token again, or press '
            'Enter to stop.');
      }
    }
  }

  Future<void> _open(Uri url) async {
    out.writeln('  $url');
    if (!await context.openUrl('$url')) {
      out.writeln('Open that link in your browser.');
    }
  }
}

String _date(DateTime time) => formatDate(LocalDate.of(time.toLocal()));

const _needsTerminal = '`geas setup` asks questions, so it needs a terminal. '
    'In scripts, use `geas init <owner/repo>` with GEAS_TOKEN set.';
