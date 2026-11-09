import 'dart:convert';

import 'package:geas_core/geas_core.dart';
import 'package:geas_core/testing.dart';
import 'package:test/test.dart';

void main() {
  test('writes geas.yaml into an empty repo', () async {
    final github = FakeGitHubClient();

    expect(await initDataRepo(github), InitOutcome.created);
    expect(utf8.decode(github.files[repoConfigPath]!), 'format: 1\n');
    expect(github.commits, ['geas init']);
  });

  test('the written file parses as the current format', () async {
    final github = FakeGitHubClient();
    await initDataRepo(github);

    final config = RepoConfig.parse(utf8.decode(github.files[repoConfigPath]!));
    expect(config.format, currentFormat);
  });

  test('uses the given commit message', () async {
    final github = FakeGitHubClient();
    await initDataRepo(github, message: 'geas init (laptop)');
    expect(github.commits, ['geas init (laptop)']);
  });

  test('leaves an initialized repo alone', () async {
    final github = FakeGitHubClient();
    github.push({repoConfigPath: utf8.encode('format: 1\nnote: hand edit\n')});

    expect(await initDataRepo(github), InitOutcome.alreadyInitialized);
    expect(
      utf8.decode(github.files[repoConfigPath]!),
      'format: 1\nnote: hand edit\n',
    );
    expect(github.commits, ['push']);
  });

  test('running twice writes once', () async {
    final github = FakeGitHubClient();
    await initDataRepo(github);
    expect(await initDataRepo(github), InitOutcome.alreadyInitialized);
    expect(github.commits, hasLength(1));
  });

  test('adds geas.yaml to a repo that has other files', () async {
    final github = FakeGitHubClient();
    github.push({'README.md': utf8.encode('# My tasks\n')});

    expect(await initDataRepo(github), InitOutcome.created);
    expect(github.files.keys, containsAll(['README.md', repoConfigPath]));
  });

  test('refuses a repo from a newer format', () async {
    final github = FakeGitHubClient();
    github.push({repoConfigPath: utf8.encode('format: 2\n')});

    await expectLater(
      initDataRepo(github),
      throwsA(isA<UnsupportedFormatException>()
          .having((e) => e.format, 'format', 2)),
    );
  });

  test('refuses a geas.yaml it cannot parse', () async {
    final github = FakeGitHubClient();
    github.push({repoConfigPath: utf8.encode('just some text\n')});

    await expectLater(initDataRepo(github), throwsFormatException);
  });

  test('another device initializing first counts as already initialized',
      () async {
    final github = _RacingClient();

    expect(await initDataRepo(github), InitOutcome.alreadyInitialized);
    expect(github.commits, ['geas init (other device)']);
  });

  test('a rejected write is reported when nothing was written', () async {
    final github = _RejectingClient();

    await expectLater(
      initDataRepo(github),
      throwsA(
          isA<GitHubException>().having((e) => e.statusCode, 'status', 422)),
    );
  });
}

/// Another device writes geas.yaml between our read and our write.
class _RacingClient extends FakeGitHubClient {
  @override
  Future<void> createFile(
    String path,
    List<int> content, {
    required String message,
  }) async {
    await super.createFile(
      path,
      utf8.encode(initialRepoConfig),
      message: 'geas init (other device)',
    );
    await super.createFile(path, content, message: message);
  }
}

/// Rejects every write as invalid, without anything being there.
class _RejectingClient extends FakeGitHubClient {
  @override
  Future<void> createFile(
    String path,
    List<int> content, {
    required String message,
  }) async {
    throw const GitHubException(422, 'Validation Failed');
  }
}
