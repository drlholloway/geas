import 'github_client.dart';

/// In-memory [GitHubClient] for tests. Starts as an empty repository.
class FakeGitHubClient implements GitHubClient {
  FakeGitHubClient({this.repo = const RepoRef('owner', 'geas-data')});

  @override
  final RepoRef repo;

  /// Files on the default branch, by path.
  final Map<String, List<int>> files = {};

  /// Commit messages, oldest first.
  final List<String> commits = [];

  @override
  Future<List<int>?> readFile(String path) async => files[path];

  @override
  Future<void> createFile(
    String path,
    List<int> content, {
    required String message,
  }) async {
    if (files.containsKey(path)) {
      throw const GitHubException(
          422, 'Invalid request. "sha" wasn\'t supplied.');
    }
    files[path] = List.of(content);
    commits.add(message);
  }
}
