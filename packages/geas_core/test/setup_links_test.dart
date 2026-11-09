import 'package:geas_core/geas_core.dart';
import 'package:geas_core/testing.dart';
import 'package:test/test.dart';

const _repo = RepoRef('drl', 'geas-data');

class _RejectingClient extends FakeGitHubClient {
  _RejectingClient(this.statusCode) : super(repo: _repo);

  final int statusCode;

  @override
  Future<RepoAccess> checkAccess() async =>
      throw GitHubException(statusCode, 'nope');
}

void main() {
  test('the token form is filled in for this device and repo', () {
    final url = newTokenUrl(_repo, 'mac', const LocalDate(2026, 11, 9));
    expect(url.path, '/settings/personal-access-tokens/new');
    expect(url.queryParameters, {
      'name': 'Geas mac 2026-11-09',
      'description': startsWith('Lets Geas on mac sync tasks with drl/'),
      'target_name': 'drl',
      'expires_in': '366',
      'contents': 'write',
    });
  });

  test('the repo form makes a private repo', () {
    expect(newRepoUrl(_repo).queryParameters, {
      'owner': 'drl',
      'name': 'geas-data',
      'visibility': 'private',
      'description': dataRepoDescription,
    });
  });

  group('checkTokenAccess', () {
    test('passes a token that can push', () async {
      final access = await checkTokenAccess(FakeGitHubClient(repo: _repo));
      expect(access.canWrite, isTrue);
    });

    Matcher problem(String text) => throwsA(
          isA<TokenProblem>()
              .having((p) => p.message, 'message', contains(text)),
        );

    test('advises on a read-only token', () {
      final client = FakeGitHubClient(repo: _repo)
        ..access = const RepoAccess(canWrite: false);
      expect(checkTokenAccess(client), problem('"Read and write"'));
    });

    test('advises on a token that can\'t see the repo', () {
      final client = FakeGitHubClient(repo: _repo)..access = null;
      expect(checkTokenAccess(client), problem('"Only select repositories"'));
    });

    test('advises on a rejected token', () {
      expect(checkTokenAccess(_RejectingClient(401)), problem('rejected'));
    });

    test('passes other errors through', () {
      expect(
        checkTokenAccess(_RejectingClient(500)),
        throwsA(isA<GitHubException>()),
      );
    });
  });
}
