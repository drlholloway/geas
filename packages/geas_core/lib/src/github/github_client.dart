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

/// GitHub refused to move the branch because it isn't an ancestor of the new
/// commit: another device pushed first.
class NotFastForwardException extends GitHubException {
  const NotFastForwardException(String message) : super(422, message);
}

/// What a token can do in a repository.
class RepoAccess {
  const RepoAccess({required this.canWrite, this.tokenExpires});

  /// Whether it can push, which sync needs.
  final bool canWrite;

  /// When the token expires, or null if it doesn't or GitHub didn't say.
  final DateTime? tokenExpires;
}

/// The slice of the GitHub REST API that Geas uses, bound to one repository
/// and one branch.
///
/// Sync and merge logic talk to this interface only, so tests run against
/// `FakeGitHubClient` from `package:geas_core/testing.dart`.
abstract interface class GitHubClient {
  RepoRef get repo;

  /// The branch that holds the data, normally `main`.
  String get branch;

  /// What the token can do in [repo]. Throws [GitHubException] with status
  /// 404 if the repo doesn't exist or the token can't see it.
  Future<RepoAccess> checkAccess();

  /// The commit at the tip of [branch], or null if the repository is empty
  /// or has no such branch.
  Future<String?> branchHead();

  /// The SHA of the tree that [commitSha] points to.
  Future<String> commitTree(String commitSha);

  /// Every file in the tree [treeSha], recursively, as path to blob SHA.
  Future<Map<String, String>> readTree(String treeSha);

  Future<List<int>> readBlob(String sha);

  /// Uploads [content] and returns its blob SHA.
  Future<String> createBlob(List<int> content);

  /// A new tree: [baseTree] with [changes] applied. Each change maps a path
  /// to a blob SHA to add or replace it, or to null to delete it.
  Future<String> createTree(String baseTree, Map<String, String?> changes);

  Future<String> createCommit({
    required String message,
    required String tree,
    required List<String> parents,
  });

  /// Moves [branch] to [commitSha] without forcing it. Throws
  /// [NotFastForwardException] if the branch has moved since [commitSha]'s
  /// parent was read.
  Future<void> updateBranch(String commitSha);

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
