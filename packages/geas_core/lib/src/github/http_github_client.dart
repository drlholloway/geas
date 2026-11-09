import 'dart:convert';

import 'package:http/http.dart' as http;

import 'github_client.dart';

/// [GitHubClient] over the GitHub REST API, authenticated with a personal
/// access token.
class HttpGitHubClient implements GitHubClient {
  HttpGitHubClient(
    this.repo, {
    required String token,
    http.Client? httpClient,
    Uri? apiBase,
  })  : _token = token,
        _http = httpClient ?? http.Client(),
        _apiBase = apiBase ?? Uri.parse('https://api.github.com');

  @override
  final RepoRef repo;
  final String _token;
  final http.Client _http;
  final Uri _apiBase;

  Uri _uri(String path) => _apiBase.replace(
        path: '/repos/${repo.owner}/${repo.name}$path',
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

  Future<void> _checkRepo() async {
    final response = await _http.get(_uri(''), headers: _headers());
    if (response.statusCode == 404) {
      throw GitHubException(
        404,
        'Repository $repo not found, or the token has no access to it.',
      );
    }
    if (response.statusCode != 200) throw _error(response);
  }

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
