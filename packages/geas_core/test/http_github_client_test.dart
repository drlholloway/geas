import 'dart:convert';

import 'package:geas_core/geas_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const _repo = RepoRef('drl', 'geas-data');

HttpGitHubClient _client(MockClientHandler handler) =>
    HttpGitHubClient(_repo, token: 'tok', httpClient: MockClient(handler));

void main() {
  group('RepoRef.parse', () {
    test('accepts owner/name', () {
      expect(RepoRef.parse(' drl/geas-data '), _repo);
    });

    for (final bad in ['geas-data', 'drl/', '/geas-data', 'a/b/c', '']) {
      test('rejects "$bad"', () {
        expect(() => RepoRef.parse(bad), throwsFormatException);
      });
    }
  });

  group('readFile', () {
    test('fetches raw contents with the token', () async {
      late http.Request seen;
      final client = _client((request) async {
        seen = request;
        return http.Response('format: 1\n', 200);
      });

      expect(utf8.decode((await client.readFile('geas.yaml'))!), 'format: 1\n');
      expect(seen.method, 'GET');
      expect(
        seen.url.toString(),
        'https://api.github.com/repos/drl/geas-data/contents/geas.yaml',
      );
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(seen.headers['Accept'], 'application/vnd.github.raw+json');
      expect(seen.headers['X-GitHub-Api-Version'], '2022-11-28');
    });

    test('returns null for a missing file in a reachable repo', () async {
      final client = _client((request) async {
        if (request.url.path.endsWith('/contents/geas.yaml')) {
          return http.Response('{"message":"This repository is empty."}', 404);
        }
        return http.Response('{"name":"geas-data"}', 200);
      });

      expect(await client.readFile('geas.yaml'), isNull);
    });

    test('throws when the repo itself is not found', () async {
      final client =
          _client((_) async => http.Response('{"message":"Not Found"}', 404));

      await expectLater(
        client.readFile('geas.yaml'),
        throwsA(isA<GitHubException>()
            .having((e) => e.statusCode, 'status', 404)
            .having((e) => e.message, 'message', contains('drl/geas-data'))),
      );
    });

    test('surfaces GitHub error messages', () async {
      final client = _client(
          (_) async => http.Response('{"message":"Bad credentials"}', 401));

      await expectLater(
        client.readFile('geas.yaml'),
        throwsA(isA<GitHubException>()
            .having((e) => e.statusCode, 'status', 401)
            .having((e) => e.message, 'message', 'Bad credentials')),
      );
    });
  });

  group('createFile', () {
    test('PUTs base64 content with a commit message', () async {
      late http.Request seen;
      final client = _client((request) async {
        seen = request;
        return http.Response('{}', 201);
      });

      await client.createFile('geas.yaml', utf8.encode('format: 1\n'),
          message: 'geas init');

      expect(seen.method, 'PUT');
      expect(seen.url.path, '/repos/drl/geas-data/contents/geas.yaml');
      final body = jsonDecode(seen.body) as Map<String, Object?>;
      expect(body['message'], 'geas init');
      expect(
          utf8.decode(base64Decode(body['content'] as String)), 'format: 1\n');
      expect(body.containsKey('sha'), isFalse);
    });

    test('throws on rejection', () async {
      final client = _client(
          (_) async => http.Response('{"message":"Invalid request."}', 422));

      await expectLater(
        client.createFile('geas.yaml', [], message: 'geas init'),
        throwsA(
            isA<GitHubException>().having((e) => e.statusCode, 'status', 422)),
      );
    });
  });

  group('Git Data API', () {
    test('branchHead reads the ref', () async {
      late http.Request seen;
      final client = _client((request) async {
        seen = request;
        return http.Response('{"object":{"sha":"c0ffee"}}', 200);
      });
      expect(await client.branchHead(), 'c0ffee');
      expect(seen.url.path, '/repos/drl/geas-data/git/ref/heads/main');
    });

    test('branchHead is null for an empty repo', () async {
      final client = _client((_) async =>
          http.Response('{"message":"Git Repository is empty."}', 409));
      expect(await client.branchHead(), isNull);
    });

    test('branchHead throws when the repo is missing', () async {
      final client =
          _client((_) async => http.Response('{"message":"Not Found"}', 404));
      await expectLater(client.branchHead(), throwsA(isA<GitHubException>()));
    });

    test('commitTree and readTree', () async {
      final client = _client((request) async {
        if (request.url.path.endsWith('/git/commits/c1')) {
          return http.Response('{"tree":{"sha":"t1"}}', 200);
        }
        expect(request.url.path, endsWith('/git/trees/t1'));
        expect(request.url.queryParameters['recursive'], '1');
        return http.Response(
            jsonEncode({
              'truncated': false,
              'tree': [
                {'path': 'tasks', 'type': 'tree', 'sha': 'd1'},
                {'path': 'tasks/a.md', 'type': 'blob', 'sha': 'b1'},
                {'path': 'geas.yaml', 'type': 'blob', 'sha': 'b2'},
              ],
            }),
            200);
      });
      expect(await client.commitTree('c1'), 't1');
      expect(
          await client.readTree('t1'), {'tasks/a.md': 'b1', 'geas.yaml': 'b2'});
    });

    test('readTree refuses a truncated listing', () async {
      final client = _client(
          (_) async => http.Response('{"truncated":true,"tree":[]}', 200));
      await expectLater(client.readTree('t'), throwsA(isA<GitHubException>()));
    });

    test('readBlob fetches raw bytes', () async {
      late http.Request seen;
      final client = _client((request) async {
        seen = request;
        return http.Response('format: 1\n', 200);
      });
      expect(utf8.decode(await client.readBlob('b1')), 'format: 1\n');
      expect(seen.headers['Accept'], 'application/vnd.github.raw+json');
    });

    test('createBlob, createTree and createCommit post JSON', () async {
      final bodies = <String, Map<String, Object?>>{};
      final client = _client((request) async {
        expect(request.method, 'POST');
        final kind = request.url.pathSegments.last;
        bodies[kind] = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response('{"sha":"$kind-sha"}', 201);
      });

      expect(await client.createBlob(utf8.encode('hi')), 'blobs-sha');
      expect(bodies['blobs'],
          {'content': base64Encode(utf8.encode('hi')), 'encoding': 'base64'});

      expect(await client.createTree('base', {'a.md': 'b1', 'gone.md': null}),
          'trees-sha');
      expect(bodies['trees'], {
        'base_tree': 'base',
        'tree': [
          {'path': 'a.md', 'mode': '100644', 'type': 'blob', 'sha': 'b1'},
          {'path': 'gone.md', 'mode': '100644', 'type': 'blob', 'sha': null},
        ],
      });

      expect(
          await client.createCommit(
              message: 'sync(mac): 1 added', tree: 't', parents: ['p']),
          'commits-sha');
      expect(bodies['commits'], {
        'message': 'sync(mac): 1 added',
        'tree': 't',
        'parents': ['p']
      });
    });

    test('updateBranch patches without force', () async {
      late http.Request seen;
      final client = _client((request) async {
        seen = request;
        return http.Response('{}', 200);
      });
      await client.updateBranch('c2');
      expect(seen.method, 'PATCH');
      expect(seen.url.path, '/repos/drl/geas-data/git/refs/heads/main');
      expect(jsonDecode(seen.body), {'sha': 'c2', 'force': false});
    });

    test('updateBranch reports a lost race', () async {
      final client = _client((_) async =>
          http.Response('{"message":"Update is not a fast forward"}', 422));
      await expectLater(
          client.updateBranch('c2'), throwsA(isA<NotFastForwardException>()));
    });
  });

  group('checkAccess', () {
    test('reads push permission and the token expiry', () async {
      final client = _client((request) async {
        expect(request.url.path, '/repos/drl/geas-data');
        return http.Response('{"permissions":{"pull":true,"push":true}}', 200,
            headers: {
              'github-authentication-token-expiration':
                  '2027-11-10 08:00:00 -0800',
            });
      });
      final access = await client.checkAccess();
      expect(access.canWrite, isTrue);
      expect(access.tokenExpires, DateTime.utc(2027, 11, 10, 16));
    });

    test('a read-only token cannot write', () async {
      final client = _client((_) async =>
          http.Response('{"permissions":{"pull":true,"push":false}}', 200));
      final access = await client.checkAccess();
      expect(access.canWrite, isFalse);
      expect(access.tokenExpires, isNull);
    });

    test('a repo the token cannot see is a 404', () async {
      final client =
          _client((_) async => http.Response('{"message":"Not Found"}', 404));
      await expectLater(
          client.checkAccess(),
          throwsA(isA<GitHubException>()
              .having((e) => e.statusCode, 'statusCode', 404)));
    });
  });

  test('parseTokenExpiration', () {
    expect(parseTokenExpiration('2027-11-10 00:00:00 UTC'),
        DateTime.utc(2027, 11, 10));
    expect(parseTokenExpiration(null), isNull);
    expect(parseTokenExpiration('soon'), isNull);
  });
}
