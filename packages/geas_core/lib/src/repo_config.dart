import 'package:yaml/yaml.dart';

/// Path of the repository config file, relative to the data repo root.
const repoConfigPath = 'geas.yaml';

/// The newest data format this build reads and writes.
const currentFormat = 1;

/// The `geas.yaml` that `geas init` writes into an empty data repo.
const initialRepoConfig = 'format: $currentFormat\n';

/// The data repo's `geas.yaml`.
class RepoConfig {
  const RepoConfig({required this.format, this.warnDays});

  /// Parses `geas.yaml`, throwing [FormatException] if it isn't a map with an
  /// integer `format`.
  factory RepoConfig.parse(String text) {
    final Object? doc;
    try {
      doc = loadYaml(text);
    } on YamlException catch (e) {
      throw FormatException('$repoConfigPath is not valid YAML: ${e.message}');
    }
    if (doc is! YamlMap || doc['format'] is! int) {
      throw const FormatException(
        '$repoConfigPath must be a map with an integer "format".',
      );
    }
    final warnDays = doc['warn_days'];
    if (warnDays != null && (warnDays is! int || warnDays < 0)) {
      throw const FormatException(
        '"warn_days" in $repoConfigPath must be a whole number of days.',
      );
    }
    return RepoConfig(format: doc['format'] as int, warnDays: warnDays as int?);
  }

  final int format;

  /// Days ahead a due date counts as approaching; null for the default.
  final int? warnDays;
}
