import 'dart:io';

import 'package:geas_core/geas_core.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'config.dart';
import 'context.dart';

/// One command's view of the data repo: the config, the local copy, and
/// syncing it.
class Session {
  Session._(this.context, this.config, {required this.offline})
      : store = DirectoryStore(storeRoot(context.dataDir, config.repo));

  /// The session for the repo `geas init` set up.
  static Future<Session> open(GeasContext context,
      {required bool offline}) async {
    final config = await CliConfig.load(context.configDir);
    if (config == null) {
      throw const CliException(
          'No data repo yet. Run `geas init <owner/repo>` first.');
    }
    return Session._(context, config, offline: offline);
  }

  /// Where the local copy of [repo] lives.
  static String storeRoot(String dataDir, RepoRef repo) =>
      p.join(dataDir, repo.owner, repo.name);

  final GeasContext context;
  final CliConfig config;
  final DirectoryStore store;

  /// Skip syncing; work on the local copy only.
  final bool offline;

  late Workspace workspace;
  Map<String, String>? _shortIds;

  /// Syncs unless offline, then loads the local copy. If GitHub can't be
  /// reached, says so and carries on with what's here.
  Future<void> pull() async {
    if (!offline) {
      try {
        await sync();
      } on Exception catch (e) {
        if (!isNetworkError(e) && e is! SyncRetriesExhaustedException) rethrow;
        _warn('${describeError(e)} Using the local copy.');
      }
    }
    await reload();
  }

  /// Syncs a change this command made. A failure only warns: the change is
  /// saved here and goes out with the next sync.
  Future<void> push() async {
    if (offline) return;
    try {
      await sync();
    } on Exception catch (e) {
      _warn('Saved here, but sync failed. ${describeError(e)} '
          'It will go out with the next sync.');
    }
  }

  /// Pulls, merges and pushes, reporting any conflicts. Uses [token] if
  /// given, otherwise [this.token].
  Future<SyncResult> sync({String? token}) async {
    final syncer = Syncer(
      github: context.connect(config.repo, token ?? await this.token()),
      store: store,
      device: config.device,
      clock: context.clock,
    );
    final result = await syncer.sync();
    for (final conflict in result.conflicts) {
      final winner = conflict.keptLocal ? 'this device' : 'the other device';
      final fields =
          conflict.fields.isEmpty ? '' : ' (${conflict.fields.join(', ')})';
      _warn('Conflict in ${conflict.path}$fields: kept the version from '
          '$winner. The other one is saved in '
          '${p.join(store.root, 'conflicts.json')}.');
    }
    return result;
  }

  /// `GEAS_TOKEN`, otherwise the stored token.
  Future<String> token() async {
    final token = context.envToken ?? await context.tokens.read(config.repo);
    if (token == null || token.isEmpty) {
      throw CliException('No GitHub token for ${config.repo}. Set GEAS_TOKEN, '
          'run `geas init` again to store one, or use --offline.');
    }
    return token;
  }

  Future<void> reload() async {
    workspace = await Workspace.load(store.working);
    _shortIds = null;
  }

  /// The short form of [id], unique among every task.
  String shortId(String id) =>
      (_shortIds ??= shortIds(workspace.tasks.map((t) => t.id)))[id] ?? id;

  /// The task [input] names, as a full id or a unique suffix.
  Task resolveTask(String input) {
    try {
      return workspace
          .task(resolveId(input, workspace.tasks.map((t) => t.id)))!;
    } on UnknownIdException catch (e) {
      throw CliException('$e');
    } on AmbiguousIdException catch (e) {
      throw CliException('"${e.input}" matches more than one task: '
          '${e.matches.map(shortId).join(', ')}. Use more of the id.');
    }
  }

  /// The list [input] names, by id or name, ignoring case.
  TaskList resolveList(String input) {
    final lists = workspace.lists;
    final lower = input.trim().toLowerCase();
    for (final list in lists) {
      if (list.id == input) return list;
    }
    for (final list in lists) {
      if (list.id.toLowerCase() == lower || list.name.toLowerCase() == lower) {
        return list;
      }
    }
    throw CliException('No list "$input". The lists are: '
        '${lists.map((l) => l.id).join(', ')}.');
  }

  void _warn(String message) => context.err.writeln('geas: $message');
}

/// The request never got an answer: offline, DNS, TLS or a dropped
/// connection.
bool isNetworkError(Object e) => e is IOException || e is http.ClientException;

/// [e] as a sentence for the user.
String describeError(Object e) => switch (e) {
      _ when isNetworkError(e) => 'Couldn\'t reach GitHub.',
      GitHubException(:final statusCode, :final message) =>
        'GitHub said: $message.${_hint(statusCode)}',
      _ => '$e',
    };

String _hint(int statusCode) => switch (statusCode) {
      401 => ' The token was rejected; check GEAS_TOKEN or run `geas init` '
          'with a new one.',
      403 => ' The token needs Contents read and write access to the repo.',
      _ => '',
    };
