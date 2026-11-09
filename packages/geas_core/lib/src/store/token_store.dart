import '../github/github_client.dart';

/// Where a device keeps the GitHub token for each data repo: the Keychain
/// or `secret-tool` for the CLI, `flutter_secure_storage` for the app.
abstract interface class TokenStore {
  Future<String?> read(RepoRef repo);
  Future<void> write(RepoRef repo, String token);
  Future<void> delete(RepoRef repo);
}

/// A [TokenStore] in memory, for tests.
class MemoryTokenStore implements TokenStore {
  final Map<RepoRef, String> tokens = {};

  @override
  Future<String?> read(RepoRef repo) async => tokens[repo];

  @override
  Future<void> write(RepoRef repo, String token) async => tokens[repo] = token;

  @override
  Future<void> delete(RepoRef repo) async => tokens.remove(repo);
}
