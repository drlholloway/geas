import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'github_client.dart';

/// The request never got an answer: offline, DNS, TLS or a dropped
/// connection.
bool isNetworkError(Object e) => e is IOException || e is http.ClientException;

/// [GitHubClient] over the GitHub REST API, authenticated with a personal
/// access token.
class HttpGitHubClient implements GitHubClient {
  HttpGitHubClient(
    this.repo, {
    required String token,
    this.branch = 'main',
    http.Client? httpClient,
    Uri? apiBase,
  })  : _token = token,
        _http = httpClient ?? http.Client(),
        _apiBase = apiBase ?? Uri.parse('https://api.github.com');

  @override
  final RepoRef repo;
  @override
  final String branch;
  final String _token;
  final http.Client _http;
  final Uri _apiBase;

  Uri _uri(String path, [Map<String, String>? query]) => _apiBase.replace(
        path: '/repos/${repo.owner}/${repo.name}$path',
        queryParameters: query,
      );

  Map<String, String> _headers(
          {String accept = 'application/vnd.github+json'}) =>
      {
        'Accept': accept,
        'Authorization': 'Bearer $_token',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'geas',
      };

  @override
  Future<List<int>?> readFile(String path) async {
    final response = await _http.get(
      _uri('/contents/$path'),
      headers: _headers(accept: 'application/vnd.github.raw+json'),
    );
    if (response.statusCode == 200) return response.bodyBytes;
    if (response.statusCode == 404) {
      // GitHub answers 404 both for a missing file and for a repository that
      // doesn't exist or that the token can't see. Tell them apart.
      await _checkRepo();
      return null;
    }
    throw _error(response);
  }

  @override
  Future<void> createFile(
    String path,
    List<int> content, {
    required String message,
  }) async {
    final response = await _http.put(
      _uri('/contents/$path'),
      headers: _headers(),
      body: jsonEncode({'message': message, 'content': base64Encode(content)}),
    );
    if (response.statusCode != 201) throw _error(response);
  }

  @override
  Future<RepoAccess> checkAccess() async {
    final response = await _http.get(_uri(''), headers: _headers());
    if (response.statusCode == 404) throw _notFound();
    if (response.statusCode != 200) throw _error(response);
    final permissions = _json(response)['permissions'];
    return RepoAccess(
      canWrite: permissions is Map && permissions['push'] == true,
      tokenExpires: parseTokenExpiration(
          response.headers['github-authentication-token-expiration']),
    );
  }

  @override
  Future<String?> branchHead() async {
    final response =
        await _http.get(_uri('/git/ref/heads/$branch'), headers: _headers());
    if (response.statusCode == 200) {
      return _json(response)['object']['sha'] as String;
    }
    // 409: "Git Repository is empty."
    if (response.statusCode == 409) return null;
    if (response.statusCode == 404) {
      await _checkRepo();
      return null;
    }
    throw _error(response);
  }

  @override
  Future<String> commitTree(String commitSha) async {
    final response =
        await _http.get(_uri('/git/commits/$commitSha'), headers: _headers());
    if (response.statusCode != 200) throw _error(response);
    return _json(response)['tree']['sha'] as String;
  }

  @override
  Future<Map<String, String>> readTree(String treeSha) async {
    final response = await _http.get(
      _uri('/git/trees/$treeSha', {'recursive': '1'}),
      headers: _headers(),
    );
    if (response.statusCode != 200) throw _error(response);
    final body = _json(response);
    if (body['truncated'] == true) {
      throw const GitHubException(
          200, 'The data repo is too large to list in one request.');
    }
    return {
      for (final entry in body['tree'] as List<dynamic>)
        if (entry['type'] == 'blob')
          entry['path'] as String: entry['sha'] as String,
    };
  }

  @override
  Future<List<int>> readBlob(String sha) async {
    final response = await _http.get(
      _uri('/git/blobs/$sha'),
      headers: _headers(accept: 'application/vnd.github.raw+json'),
    );
    if (response.statusCode != 200) throw _error(response);
    return response.bodyBytes;
  }

  @override
  Future<String> createBlob(List<int> content) async {
    final response = await _http.post(
      _uri('/git/blobs'),
      headers: _headers(),
      body:
          jsonEncode({'content': base64Encode(content), 'encoding': 'base64'}),
    );
    if (response.statusCode != 201) throw _error(response);
    return _json(response)['sha'] as String;
  }

  @override
  Future<String> createTree(
      String baseTree, Map<String, String?> changes) async {
    final response = await _http.post(
      _uri('/git/trees'),
      headers: _headers(),
      body: jsonEncode({
        'base_tree': baseTree,
        'tree': [
          for (final MapEntry(key: path, value: sha) in changes.entries)
            {'path': path, 'mode': '100644', 'type': 'blob', 'sha': sha},
        ],
      }),
    );
    if (response.statusCode != 201) throw _error(response);
    return _json(response)['sha'] as String;
  }

  @override
  Future<String> createCommit({
    required String message,
    required String tree,
    required List<String> parents,
  }) async {
    final response = await _http.post(
      _uri('/git/commits'),
      headers: _headers(),
      body: jsonEncode({'message': message, 'tree': tree, 'parents': parents}),
    );
    if (response.statusCode != 201) throw _error(response);
    return _json(response)['sha'] as String;
  }

  @override
  Future<void> updateBranch(String commitSha) async {
    final response = await _http.patch(
      _uri('/git/refs/heads/$branch'),
      headers: _headers(),
      body: jsonEncode({'sha': commitSha, 'force': false}),
    );
    if (response.statusCode == 200) return;
    final error = _error(response);
    if (response.statusCode == 422) {
      throw NotFastForwardException(error.message);
    }
    throw error;
  }

  Future<void> _checkRepo() async {
    final response = await _http.get(_uri(''), headers: _headers());
    if (response.statusCode == 404) throw _notFound();
    if (response.statusCode != 200) throw _error(response);
  }

  GitHubException _notFound() => GitHubException(
        404,
        'Repository $repo not found, or the token has no access to it.',
      );

  Map<String, dynamic> _json(http.Response response) =>
      jsonDecode(response.body) as Map<String, dynamic>;

  GitHubException _error(http.Response response) {
    var message = response.reasonPhrase ?? 'request failed';
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['message'] is String) {
        message = body['message'] as String;
      }
    } on FormatException {
      // Not JSON; keep the reason phrase.
    }
    return GitHubException(response.statusCode, message);
  }
}

final _expirationPattern =
    RegExp(r'^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}) (UTC|[+-]\d{4})$');

/// Parses GitHub's `GitHub-Authentication-Token-Expiration` header, such as
/// `2027-11-10 00:00:00 UTC` or `2027-11-10 00:00:00 -0800`; null if
/// [header] is missing or in another form.
DateTime? parseTokenExpiration(String? header) {
  final m = _expirationPattern.firstMatch(header?.trim() ?? '');
  if (m == null) return null;
  final zone =
      m[3] == 'UTC' ? 'Z' : '${m[3]!.substring(0, 3)}:${m[3]!.substring(3)}';
  return DateTime.tryParse('${m[1]}T${m[2]}$zone')?.toUtc();
}
