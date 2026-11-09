import '../local_date.dart';
import 'github_client.dart';

// Links to GitHub forms, filled in for setting Geas up. GitHub has no API
// for creating fine-grained tokens, so the CLI and app open these instead.

/// Days a new token lasts: the most GitHub allows.
const tokenLifetimeDays = 366;

/// The GitHub form for a new fine-grained token, filled in for Geas on
/// [device]: name, description, owner, a year's expiry and Contents read
/// and write. GitHub can't pre-select the repository.
Uri newTokenUrl(RepoRef repo, String device, LocalDate today) {
  // Token names are unique per account and at most 40 characters, so the
  // date goes on the end and the device is cut to fit.
  var label = 'Geas $device';
  if (label.length > 29) label = label.substring(0, 29).trimRight();
  return Uri.https('github.com', '/settings/personal-access-tokens/new', {
    'name': '$label $today',
    'description': 'Lets Geas on $device sync tasks with $repo. Repository '
        'access: only $repo. Made by Geas setup.',
    'target_name': repo.owner,
    'expires_in': '$tokenLifetimeDays',
    'contents': 'write',
  });
}

/// The GitHub form for a new private repository named [repo].
Uri newRepoUrl(RepoRef repo) => Uri.https('github.com', '/new', {
      'owner': repo.owner,
      'name': repo.name,
      'visibility': 'private',
      'description': dataRepoDescription,
    });

/// The description setup gives a new data repo.
const dataRepoDescription = 'Geas tasks';

/// Why a token won't do for a data repo, worded as advice.
class TokenProblem implements Exception {
  const TokenProblem(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Checks that the token behind [client] can push to its repo. Throws
/// [TokenProblem] with advice when it can't; other errors, like a network
/// failure, pass through.
Future<RepoAccess> checkTokenAccess(GitHubClient client) async {
  final repo = client.repo;
  final RepoAccess access;
  try {
    access = await client.checkAccess();
  } on GitHubException catch (e) {
    throw switch (e.statusCode) {
      401 => const TokenProblem(
          'GitHub rejected the token. Copy it again, or create a new one.'),
      404 => TokenProblem('The token can\'t see $repo. Check the name, and '
          'on GitHub edit the token: under Repository access, choose "Only '
          'select repositories" and add $repo.'),
      _ => e,
    };
  }
  if (!access.canWrite) {
    throw TokenProblem('The token can read $repo but not write to it. On '
        'GitHub, edit the token and set Contents to "Read and write".');
  }
  return access;
}
