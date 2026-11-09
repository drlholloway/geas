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
}
