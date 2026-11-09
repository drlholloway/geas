import 'dart:convert';

import 'github/github_client.dart';
import 'repo_config.dart';

enum InitOutcome {
  /// `geas.yaml` was written; the repo is now a Geas data repo.
  created,

  /// `geas.yaml` was already there, in a format this build understands.
  alreadyInitialized,
}

/// The data repo was initialized by a newer Geas than this one.
class UnsupportedFormatException implements Exception {
  const UnsupportedFormatException(this.format);

  final int format;

  @override
  String toString() =>
      'The data repo uses format $format, but this version of Geas only '
      'understands up to format $currentFormat. Update Geas.';
}

/// Makes the repository behind [client] a Geas data repo by writing
/// `geas.yaml`, unless it already has one.
///
/// Safe to run on every device: a repo that is already initialized is left
/// alone, and so is one initialized by another device mid-call. This is the
/// only write that uses the Contents API, because the Git Data API that sync
/// uses refuses to commit to an empty repository.
Future<InitOutcome> initDataRepo(
  GitHubClient client, {
  String message = 'geas init',
}) async {
  if (await _checkExisting(client)) return InitOutcome.alreadyInitialized;
  try {
    await client.createFile(
      repoConfigPath,
      utf8.encode(initialRepoConfig),
      message: message,
    );
    return InitOutcome.created;
  } on GitHubException catch (e) {
    if (e.statusCode != 409 && e.statusCode != 422) rethrow;
    // Another device may have written it between the read and the write.
    if (await _checkExisting(client)) return InitOutcome.alreadyInitialized;
    rethrow;
  }
}

/// Whether `geas.yaml` exists, after checking that its format is supported.
Future<bool> _checkExisting(GitHubClient client) async {
  final bytes = await client.readFile(repoConfigPath);
  if (bytes == null) return false;
  final config = RepoConfig.parse(utf8.decode(bytes));
  if (config.format > currentFormat) {
    throw UnsupportedFormatException(config.format);
  }
  return true;
}
