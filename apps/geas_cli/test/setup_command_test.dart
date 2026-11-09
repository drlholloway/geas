import 'dart:io';

import 'package:geas_cli/geas_cli.dart';
import 'package:geas_core/geas_core.dart';
import 'package:test/test.dart';

import 'harness.dart';

void main() {
  late Harness geas;
  late List<List<String>> ghCalls;
  final expires = DateTime.utc(2027, 11, 10, 16);

  setUp(() async {
    geas = await Harness.create();
    geas.github.access = RepoAccess(canWrite: true, tokenExpires: expires);
    geas.typedToken = 'github_pat_new';
    ghCalls = [];
  });
  tearDown(() => geas.dispose());

  /// `gh` logged in as drl; [repoView] answers `gh repo view`, null for a
  /// missing repo.
  void withGh({String? repoView, int createExit = 0}) {
    geas.programs = (exe, args) async {
      expect(exe, 'gh');
      ghCalls.add(args);
      final (code, out) = switch (args) {
        ['api', 'user', ...] => (0, 'drl\n'),
        ['repo', 'view', ...] => repoView == null ? (1, '') : (0, repoView),
        ['repo', 'create', ...] => (createExit, ''),
        _ => throw StateError('unexpected gh $args'),
      };
      return ProcessResult(1, code, out, code == 0 ? '' : 'gh failed');
    };
  }

  test('with gh: creates the repo, opens the token form, connects', () async {
    withGh();
    geas.confirmAnswer = true;
    geas.answers.addAll(['', '', '']); // device, owner and name defaults
    expect(await geas(['setup']), 0, reason: '${geas.err}');

    expect(ghCalls.last, [
      'repo', 'create', 'drl/geas-data', '--private', //
      '--description', 'Geas tasks',
    ]);
    expect(geas.prompts, contains('GitHub account that owns it [drl]: '));
    final url = Uri.parse(geas.openedUrls.single);
    expect(url.path, '/settings/personal-access-tokens/new');
    expect(url.queryParameters, {
      'name': 'Geas testbox 2026-11-09',
      'description': contains('only drl/geas-data'),
      'target_name': 'drl',
      'expires_in': '366',
      'contents': 'write',
    });

    final out = '${geas.out}';
    expect(out, contains('Created drl/geas-data.'));
    expect(out, contains('Initialized drl/geas-data'));
    expect(out, contains('The token expires Wed 2027-11-10'));
    expect(await geas.tokens.read(repo), 'github_pat_new');
    final config = (await CliConfig.load(geas.configDir))!;
    expect((config.repo, config.device, config.tokenExpires),
        (repo, 'testbox', expires));
  });

  test('without gh: opens a filled-in repo form first', () async {
    geas.answers.addAll(['mac', 'drl', 'geas-data', '']);
    expect(await geas(['setup']), 0, reason: '${geas.err}');
    final repoUrl = Uri.parse(geas.openedUrls.first);
    expect(repoUrl.path, '/new');
    expect(repoUrl.queryParameters, {
      'owner': 'drl',
      'name': 'geas-data',
      'visibility': 'private',
      'description': 'Geas tasks',
    });
    expect(geas.prompts, contains('Press Enter when drl/geas-data exists. '));
    expect(Uri.parse(geas.openedUrls.last).queryParameters['name'],
        'Geas mac 2026-11-09');
  });

  test('an existing private repo is used as is', () async {
    withGh(repoView: 'PRIVATE\n');
    geas.answers.addAll(['', '', '']);
    expect(await geas(['setup']), 0);
    expect('${geas.out}', contains('Found drl/geas-data, and it\'s private.'));
    expect(ghCalls.where((c) => c[1] == 'create'), isEmpty);
  });

  test('a public repo needs a yes', () async {
    withGh(repoView: 'PUBLIC\n');
    geas.answers.addAll(['', '', '']);
    expect(await geas(['setup']), 1);
    expect('${geas.err}', contains('anyone who can see it'));
  });

  test('explains a token that cannot see the repo, then takes another',
      () async {
    geas.typedToken = 'github_pat_wrong_repo';
    geas.moreTokens.add('github_pat_right');
    geas.onConnect = (token) => geas.github.access = token.endsWith('right')
        ? RepoAccess(canWrite: true, tokenExpires: expires)
        : null;
    geas.answers.addAll(['', 'drl', '', '']);
    expect(await geas(['setup']), 0, reason: '${geas.err}');
    expect('${geas.err}', contains('Only select repositories'));
    expect(await geas.tokens.read(repo), 'github_pat_right');
  });

  test('explains a read-only token', () async {
    geas.github.access = const RepoAccess(canWrite: false);
    geas.answers.addAll(['', 'drl', '', '']);
    expect(await geas(['setup']), 1);
    expect('${geas.err}', contains('"Read and write"'));
  });

  test('warns about a classic token', () async {
    geas.typedToken = 'ghp_classic';
    geas.answers.addAll(['', 'drl', '', '']);
    expect(await geas(['setup']), 1);
    expect('${geas.err}', contains('classic token'));
    expect(geas.tokens.tokens, isEmpty);
  });

  test('keeps a working stored token unless asked for a new one', () async {
    await geas.tokens.write(repo, 'github_pat_old');
    geas.answers.addAll(['', 'drl', '', '']);
    expect(await geas(['setup']), 0);
    expect('${geas.out}', contains('already has a working token'));
    expect(
        geas.openedUrls.where((u) => u.contains('personal-access')), isEmpty);
    expect(await geas.tokens.read(repo), 'github_pat_old');
  });

  test('needs a terminal', () async {
    expect(await geas(['setup']), 1);
    expect('${geas.err}', contains('needs a terminal'));
  });

  test('token names stay within 40 characters', () {
    final name = newTokenUrl(repo, 'a-really-long-device-name-for-a-laptop',
            const LocalDate(2026, 11, 9))
        .queryParameters['name']!;
    expect(name.length, lessThanOrEqualTo(40));
    expect(name, endsWith(' 2026-11-09'));
  });

  group('expiry reminders', () {
    Future<void> saveExpiring(DateTime when) async {
      await geas.init();
      await CliConfig(repo: repo, device: 'testbox', tokenExpires: when)
          .save(geas.configDir);
    }

    test('within two weeks', () async {
      await saveExpiring(geas.now.add(const Duration(days: 5, hours: 1)));
      expect(await geas(['ls', '--offline']), 0);
      expect('${geas.err}', contains('expires in 5 days'));
      expect('${geas.err}', contains('geas setup'));
    });

    test('expired', () async {
      await saveExpiring(geas.now.subtract(const Duration(days: 1)));
      expect(await geas(['ls', '--offline']), 0);
      expect('${geas.err}', contains('expired'));
    });

    test('not yet', () async {
      await saveExpiring(geas.now.add(const Duration(days: 60)));
      expect(await geas(['ls', '--offline']), 0);
      expect('${geas.err}', isEmpty);
    });
  });
}
