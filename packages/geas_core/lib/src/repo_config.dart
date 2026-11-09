import 'package:yaml/yaml.dart';

/// Path of the repository config file, relative to the data repo root.
const repoConfigPath = 'geas.yaml';

/// The newest data format this build reads and writes.
const currentFormat = 1;

/// The `geas.yaml` that `geas init` writes into an empty data repo.
const initialRepoConfig = 'format: $currentFormat\n';

/// The data repo's `geas.yaml`.
class RepoConfig {
  const RepoConfig({required this.format});

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
    return RepoConfig(format: doc['format'] as int);
  }

  final int format;
}
