import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geas_core/geas_core.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'background_sync.dart';
import 'desktop_background.dart';
import 'home_widget.dart';
import 'reminders.dart';

const _keep = Object();

/// How often a device syncs on its own unless told otherwise, and the
/// shortest Android's WorkManager allows.
const defaultSyncMinutes = 30;
const minSyncMinutes = 15;

/// The intervals Settings offers, in minutes.
const syncMinuteChoices = [15, 30, 60, 120, 240];

/// Which data repo this device syncs with, and as what.
class AppConfig {
  const AppConfig({
    required this.repo,
    required this.device,
    this.tokenExpires,
    this.backgroundSync = true,
    this.syncMinutes = defaultSyncMinutes,
    this.reminders = false,
    this.collapsedFolders = const [],
    this.reminderMinutes = reminderHour * 60,
  });

  factory AppConfig.fromJson(Map<String, Object?> json) => AppConfig(
    repo: RepoRef.parse(json['repo']! as String),
    device: json['device']! as String,
    tokenExpires: switch (json['token_expires']) {
      final String text => DateTime.parse(text),
      _ => null,
    },
    backgroundSync: json['background_sync'] as bool? ?? true,
    syncMinutes: switch (json['sync_minutes']) {
      final int minutes when minutes >= minSyncMinutes => minutes,
      _ => defaultSyncMinutes,
    },
    reminders: json['reminders'] as bool? ?? false,
    collapsedFolders: switch (json['collapsed_folders']) {
      final List<Object?> ids => [for (final id in ids) '$id'],
      _ => const [],
    },
    reminderMinutes: switch (json['reminder_minutes']) {
      final int minutes when minutes >= 0 && minutes < 24 * 60 => minutes,
      _ => reminderHour * 60,
    },
  );

  final RepoRef repo;

  /// Names this device in sync commits.
  final String device;

  /// When the stored token stops working, if GitHub said.
  final DateTime? tokenExpires;

  /// Whether this device syncs on its own every [syncMinutes]: in the
  /// background on Android, and while the app is open everywhere.
  final bool backgroundSync;

  /// Minutes between those syncs; Android won't go below [minSyncMinutes].
  final int syncMinutes;

  /// Whether this device shows a notification when a task comes due, or a
  /// medication or sensor is due again.
  final bool reminders;

  /// When this device announces a task that has a due date but no time,
  /// in minutes past midnight.
  final int reminderMinutes;

  /// The ids of the folders closed in this device's sidebar.
  final List<String> collapsedFolders;

  /// A copy with the given fields replaced. Pass null for [tokenExpires] to
  /// clear it.
  AppConfig copyWith({
    Object? tokenExpires = _keep,
    bool? backgroundSync,
    int? syncMinutes,
    bool? reminders,
    List<String>? collapsedFolders,
    int? reminderMinutes,
  }) => AppConfig(
    repo: repo,
    device: device,
    tokenExpires: identical(tokenExpires, _keep)
        ? this.tokenExpires
        : tokenExpires as DateTime?,
    backgroundSync: backgroundSync ?? this.backgroundSync,
    syncMinutes: syncMinutes ?? this.syncMinutes,
    reminders: reminders ?? this.reminders,
    collapsedFolders: collapsedFolders ?? this.collapsedFolders,
    reminderMinutes: reminderMinutes ?? this.reminderMinutes,
  );

  Map<String, Object?> toJson() => {
    'repo': '$repo',
    'device': device,
    if (tokenExpires != null)
      'token_expires': tokenExpires!.toUtc().toIso8601String(),
    if (!backgroundSync) 'background_sync': false,
    if (syncMinutes != defaultSyncMinutes) 'sync_minutes': syncMinutes,
    if (reminders) 'reminders': true,
    if (collapsedFolders.isNotEmpty) 'collapsed_folders': collapsedFolders,
    if (reminderMinutes != reminderHour * 60)
      'reminder_minutes': reminderMinutes,
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
    this.backgroundScheduler,
    this.reminders,
    this.supportDir,
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
      backgroundScheduler: Platform.isAndroid
          ? const AndroidBackgroundScheduler()
          // Only a release build schedules itself on a desktop: a debug
          // build would leave the system starting a binary that changes
          // or goes away.
          : !kReleaseMode
          ? null
          : Platform.isMacOS
          ? const MacAgentScheduler()
          : Platform.isLinux
          ? LinuxSystemdScheduler()
          : null,
      supportDir: dir,
      reminders: LocalNotifications(
        supportDir: dir,
        linuxWake: kReleaseMode && Platform.isLinux
            ? LinuxReminderWake()
            : null,
      ),
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

  /// Schedules syncs while the app is closed, on Android. Elsewhere the
  /// app only syncs while it's open.
  final BackgroundScheduler? backgroundScheduler;

  /// Shows reminders as notifications; null where that can't be done.
  final ReminderHost? reminders;

  /// Where the app keeps its files, or null in tests.
  final String? supportDir;

  /// This build's version, as in pubspec.yaml.
  final String version;
}

final environmentProvider = Provider<AppEnvironment>(
  (ref) => throw UnimplementedError('main() overrides environmentProvider'),
);
