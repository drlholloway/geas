import 'dart:convert';

import 'package:geas_cli/geas_cli.dart';
import 'package:geas_core/geas_core.dart';
import 'package:test/test.dart';

import 'harness.dart';

void main() {
  late Harness geas;

  setUp(() async => geas = await Harness.create());
  tearDown(() => geas.dispose());

  test('init writes geas.yaml, remembers the repo and stores the token',
      () async {
    expect(await geas(['init', 'drl/geas-data']), 0, reason: '${geas.err}');
    expect(geas.remote(repoConfigPath), initialRepoConfig);
    expect(geas.out.toString(), contains('Initialized drl/geas-data'));
    expect(geas.out.toString(), contains('Stored the token.'));
    expect(geas.out.toString(), contains('This device is "testbox"'));
    expect(geas.connections, everyElement('typed_token'));
    expect(await geas.tokens.read(repo), 'typed_token');

    final config = (await CliConfig.load(geas.configDir))!;
    expect(config.repo, repo);
    expect(config.device, 'testbox');
  });

  test('init pulls the tasks already there', () async {
    geas.github.push({repoConfigPath: utf8.encode(initialRepoConfig)});
    geas.pushTask('01AAAAAAAAAAAAAAAAAAAAAAAA', 'From the phone');

    expect(await geas(['init', 'drl/geas-data']), 0);
    expect(geas.out.toString(), contains('already a Geas data repo'));
    expect(geas.out.toString(), contains('Synced: 1 open task'));
    expect(geas.github.commits, ['push', 'other device']);

    expect(await geas(['ls', '--offline']), 0);
    expect(geas.out.toString(), contains('From the phone'));
  });

  test('a token from GEAS_TOKEN is used but not stored', () async {
    geas.envToken = 'env_token';
    expect(await geas(['init', 'drl/geas-data']), 0);
    expect(geas.connections, everyElement('env_token'));
    expect(geas.tokens.tokens, isEmpty);
    expect(geas.out.toString(), isNot(contains('Stored')));
  });

  test('a stored token is reused without asking', () async {
    await geas.tokens.write(repo, 'stored_token');
    geas.typedToken = null;
    expect(await geas(['init', 'drl/geas-data']), 0);
    expect(geas.connections, everyElement('stored_token'));
  });

  test('init again uses the saved repo; --device renames the device', () async {
    await geas.init();
    expect(await geas(['init', '--device', 'mac']), 0);
    expect(geas.out.toString(), contains('already a Geas data repo'));
    expect((await CliConfig.load(geas.configDir))!.device, 'mac');

    expect(await geas(['init']), 0);
    expect((await CliConfig.load(geas.configDir))!.device, 'mac');
  });

  test('init needs a repo the first time', () async {
    expect(await geas(['init']), 64);
    expect(geas.err.toString(), contains('owner/repo'));
  });

  test('init rejects a malformed repo', () async {
    expect(await geas(['init', 'geas-data']), 64);
    expect(geas.connections, isEmpty);
  });

  test('init needs a token', () async {
    geas.typedToken = null;
    expect(await geas(['init', 'drl/geas-data']), 64);
    expect(geas.err.toString(), contains('GEAS_TOKEN'));
    expect(geas.connections, isEmpty);
  });

  test('init reports a newer data format', () async {
    geas.github.push({repoConfigPath: utf8.encode('format: 9\n')});
    expect(await geas(['init', 'drl/geas-data']), 1);
    expect(geas.err.toString(), contains('format 9'));
  });

  test('other commands need init first', () async {
    expect(await geas(['ls']), 1);
    expect(geas.err.toString(), contains('geas init'));
  });

  test('commands need a token once the stored one is gone', () async {
    await geas.init();
    geas.tokens.tokens.clear();
    expect(await geas(['ls']), 1);
    expect(geas.err.toString(), contains('No GitHub token'));
    expect(await geas(['ls', '--offline']), 0);
  });
}
