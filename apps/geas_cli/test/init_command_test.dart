import 'dart:convert';

import 'package:geas_cli/geas_cli.dart';
import 'package:geas_core/geas_core.dart';
import 'package:geas_core/testing.dart';
import 'package:test/test.dart';

void main() {
  late FakeGitHubClient github;
  late StringBuffer out;
  late StringBuffer err;
  RepoRef? connectedRepo;
  String? connectedToken;

  setUp(() {
    github = FakeGitHubClient();
    out = StringBuffer();
    err = StringBuffer();
    connectedRepo = null;
    connectedToken = null;
  });

  Future<int> geas(List<String> args, {String? token = 'tok'}) => runGeas(
        args,
        connect: (repo, t) {
          connectedRepo = repo;
          connectedToken = t;
          return github;
        },
        readToken: () => token,
        out: out,
        err: err,
      );

  test('init writes geas.yaml into an empty repo', () async {
    expect(await geas(['init', 'drl/geas-data']), 0);
    expect(connectedRepo, const RepoRef('drl', 'geas-data'));
    expect(connectedToken, 'tok');
    expect(utf8.decode(github.files[repoConfigPath]!), initialRepoConfig);
    expect(out.toString(), 'Initialized drl/geas-data: wrote geas.yaml.\n');
  });

  test('init on an initialized repo changes nothing', () async {
    github.push({repoConfigPath: utf8.encode(initialRepoConfig)});

    expect(await geas(['init', 'drl/geas-data']), 0);
    expect(github.commits, ['push']);
    expect(out.toString(), contains('already a Geas data repo'));
  });

  test('init needs a repo', () async {
    expect(await geas(['init']), 64);
    expect(err.toString(), contains('owner/repo'));
  });

  test('init rejects a malformed repo', () async {
    expect(await geas(['init', 'geas-data']), 64);
    expect(connectedRepo, isNull);
  });

  test('init needs a token', () async {
    expect(await geas(['init', 'drl/geas-data'], token: null), 64);
    expect(err.toString(), contains('GEAS_TOKEN'));
    expect(connectedRepo, isNull);
  });

  test('init reports a newer data format', () async {
    github.push({repoConfigPath: utf8.encode('format: 9\n')});

    expect(await geas(['init', 'drl/geas-data']), 1);
    expect(err.toString(), contains('format 9'));
  });
}
