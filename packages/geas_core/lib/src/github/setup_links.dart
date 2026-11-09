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
