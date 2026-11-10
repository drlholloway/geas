import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geas_core/geas_core.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'home_widget.dart';

/// Which data repo this device syncs with, and as what.
class AppConfig {
  const AppConfig({
    required this.repo,
    required this.device,
    this.tokenExpires,
  });

  factory AppConfig.fromJson(Map<String, Object?> json) => AppConfig(
    repo: RepoRef.parse(json['repo']! as String),
    device: json['device']! as String,
    tokenExpires: switch (json['token_expires']) {
      final String text => DateTime.parse(text),
      _ => null,
    },
  );

  final RepoRef repo;

  /// Names this device in sync commits.
  final String device;

  /// When the stored token stops working, if GitHub said.
  final DateTime? tokenExpires;

  Map<String, Object?> toJson() => {
    'repo': '$repo',
    'device': device,
    if (tokenExpires != null)
      'token_expires': tokenExpires!.toUtc().toIso8601String(),
  };
}

/// Where the app keeps its [AppConfig].
abstract interface class ConfigStore {
  Future<AppConfig?> load();

  /// Saves [config], or forgets it if null.
  Future<void> save(AppConfig? config);
}

/// A [ConfigStore] in `config.json` under [dir].
class FileConfigStore implements ConfigStore {
  FileConfigStore(String dir) : _file = File(p.join(dir, 'config.json'));

  final File _file;

  @override
  Future<AppConfig?> load() async {
    if (!await _file.exists()) return null;
    try {
      final json = jsonDecode(await _file.readAsString());
      return AppConfig.fromJson((json as Map).cast());
    } on Object {
      // Unreadable: start over with setup rather than crash.
      return null;
    }
  }

  @override
  Future<void> save(AppConfig? config) async {
    if (config == null) {
      if (await _file.exists()) await _file.delete();
      return;
    }
    await _file.parent.create(recursive: true);
    final temp = File('${_file.path}.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );
    await temp.rename(_file.path);
  }
}

/// A [ConfigStore] in memory, for tests.
class MemoryConfigStore implements ConfigStore {
  MemoryConfigStore([this.config]);

  AppConfig? config;

  @override
  Future<AppConfig?> load() async => config;

  @override
  Future<void> save(AppConfig? config) async => this.config = config;
}

/// Tokens in the platform's secret store: the Keychain on macOS, the
/// Android Keystore, and the Secret Service (libsecret) on Linux.
class SecureTokenStore implements TokenStore {
  // The legacy Keychain needs no Keychain Sharing entitlement, so the app
  // runs without a provisioning profile.
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  static String _key(RepoRef repo) => 'github-token:$repo';

  @override
  Future<String?> read(RepoRef repo) => _storage.read(key: _key(repo));

  @override
  Future<void> write(RepoRef repo, String token) =>
      _storage.write(key: _key(repo), value: token);

  @override
  Future<void> delete(RepoRef repo) => _storage.delete(key: _key(repo));
}

/// Everything the app reaches outside itself for. Tests swap in fakes.
class AppEnvironment {
  const AppEnvironment({
    required this.config,
    required this.tokens,
    required this.openStore,
    required this.connect,
    required this.openUrl,
    required this.hostname,
    this.homeWidget,
    this.version = '',
  });

  /// The real thing, with files under the app support directory.
  static Future<AppEnvironment> platform() async {
    final dir = (await getApplicationSupportDirectory()).path;
    final client = http.Client();
    final host = Platform.localHostname.replaceAll(RegExp(r'\.local$'), '');
    return AppEnvironment(
      config: FileConfigStore(dir),
      tokens: SecureTokenStore(),
      openStore: (repo) =>
          DirectoryStore(p.join(dir, 'data', repo.owner, repo.name)),
      connect: (repo, token) =>
          HttpGitHubClient(repo, token: token, httpClient: client),
      openUrl: (url) => launchUrl(url, mode: LaunchMode.externalApplication),
      hostname: host.isEmpty || host == 'localhost'
          ? Platform.operatingSystem
          : host,
      homeWidget: Platform.isAndroid ? AndroidHomeWidget() : null,
      version: (await PackageInfo.fromPlatform()).version,
    );
  }

  final ConfigStore config;
  final TokenStore tokens;

  /// The local copy of a data repo.
  final SyncStore Function(RepoRef repo) openStore;

  final GitHubClient Function(RepoRef repo, String token) connect;

  /// Opens [url] in the browser; false if it couldn't.
  final Future<bool> Function(Uri url) openUrl;

  /// The default device name.
  final String hostname;

  /// The home-screen matrix widget, on Android.
  final HomeWidgetHost? homeWidget;

  /// This build's version, as in pubspec.yaml.
  final String version;
}

final environmentProvider = Provider<AppEnvironment>(
  (ref) => throw UnimplementedError('main() overrides environmentProvider'),
);
