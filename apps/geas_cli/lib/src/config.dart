import 'dart:io';

import 'package:geas_core/geas_core.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The CLI's settings, `config.yaml` in the config directory:
///
/// ```yaml
/// repo: drlholloway/geas-data
/// device: mac
/// ```
class CliConfig {
  const CliConfig({required this.repo, required this.device});

  final RepoRef repo;

  /// Names this device in sync commits.
  final String device;

  static String path(String configDir) => p.join(configDir, 'config.yaml');

  /// The saved config, or null if `geas init` hasn't run.
  static Future<CliConfig?> load(String configDir) async {
    final file = File(path(configDir));
    if (!await file.exists()) return null;
    final yaml = loadYaml(await file.readAsString());
    if (yaml is! YamlMap || yaml['repo'] is! String) {
      throw FormatException('${file.path} has no "repo".');
    }
    return CliConfig(
      repo: RepoRef.parse(yaml['repo'] as String),
      device: yaml['device'] is String ? yaml['device'] as String : 'cli',
    );
  }

  Future<void> save(String configDir) async {
    await Directory(configDir).create(recursive: true);
    await File(path(configDir)).writeAsString(
      'repo: $repo\n'
      'device: ${_quoteIfNeeded(device)}\n',
    );
  }
}

String _quoteIfNeeded(String value) =>
    RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value)
        ? value
        : '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
