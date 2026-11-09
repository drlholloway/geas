/// A GitHub repository, as `owner/name`.
class RepoRef {
  const RepoRef(this.owner, this.name);

  /// Parses `owner/name`, throwing [FormatException] for anything else.
  factory RepoRef.parse(String text) {
    final parts = text.trim().split('/');
    if (parts.length != 2 || parts.any((p) => p.isEmpty)) {
      throw FormatException('Expected owner/name, got "$text".');
    }
    return RepoRef(parts[0], parts[1]);
  }

  final String owner;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is RepoRef && other.owner == owner && other.name == name;

  @override
  int get hashCode => Object.hash(owner, name);

  @override
  String toString() => '$owner/$name';
}

/// A non-success response from the GitHub API.
class GitHubException implements Exception {
  const GitHubException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'GitHub API error $statusCode: $message';
}

/// The slice of the GitHub REST API that Geas uses, bound to one repository.
///
/// Sync and merge logic talk to this interface only, so tests run against
/// `FakeGitHubClient` from `package:geas_core/testing.dart`.
abstract interface class GitHubClient {
  RepoRef get repo;

  /// The contents of [path] on the default branch, or null if there is no
  /// such file. An empty repository has no files.
  ///
  /// Throws [GitHubException] if the repository itself can't be reached.
  Future<List<int>?> readFile(String path);

  /// Creates [path] on the default branch through the Contents API.
  ///
  /// Unlike the Git Data API, this works on an empty repository, so it is how
  /// `geas init` makes the first commit. Throws [GitHubException] with status
  /// 409 or 422 if the file already exists.
  Future<void> createFile(
    String path,
    List<int> content, {
    required String message,
  });
}
