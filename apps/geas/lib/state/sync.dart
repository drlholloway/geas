import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';

import 'environment.dart';
import 'session.dart';
import 'store.dart';

/// How long after an edit the app syncs, so a burst of edits goes out as
/// one commit.
const syncDelay = Duration(seconds: 5);

/// How the last sync went.
class SyncStatus {
  const SyncStatus({
    this.syncing = false,
    this.lastSynced,
    this.error,
    this.offline = false,
    this.fixInSettings = false,
    this.conflicts = 0,
  });

  final bool syncing;
  final DateTime? lastSynced;

  /// Why the last sync failed, as a sentence; null if it worked.
  final String? error;

  /// The last sync failed because GitHub couldn't be reached.
  final bool offline;

  /// The token needs replacing.
  final bool fixInSettings;

  /// Conflicts sync resolved that haven't been dismissed.
  final int conflicts;

  SyncStatus _started() => SyncStatus(
    syncing: true,
    lastSynced: lastSynced,
    error: error,
    offline: offline,
    fixInSettings: fixInSettings,
    conflicts: conflicts,
  );
}

/// Syncs the local copy with the data repo: when asked, and [syncDelay]
/// after edits. One sync at a time; asking during one runs another after.
class SyncController extends Notifier<SyncStatus> {
  Timer? _timer;
  Future<void>? _running;
  var _again = false;

  @override
  SyncStatus build() {
    ref.watch(sessionProvider);
    ref.onDispose(() => _timer?.cancel());
    return const SyncStatus();
  }

  /// Syncs [syncDelay] from now, unless something else asks first.
  void schedule() {
    _timer?.cancel();
    _timer = Timer(syncDelay, sync);
  }

  Future<void> sync() async {
    _timer?.cancel();
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final run = _running = _run();
    try {
      await run;
    } finally {
      _running = null;
    }
    if (_again && ref.mounted) {
      _again = false;
      await sync();
    }
  }

  Future<void> _run() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final env = ref.read(environmentProvider);
    final clock = ref.read(clockProvider);
    final tasks = ref.read(taskStoreProvider.notifier);
    state = state._started();
    SyncStatus next;
    try {
      final token = await env.tokens.read(session.repo);
      if (token == null || token.isEmpty) {
        next = SyncStatus(
          lastSynced: state.lastSynced,
          error: 'This device has no token for ${session.repo}.',
          fixInSettings: true,
        );
      } else {
        await tasks.flush();
        await Syncer(
          github: env.connect(session.repo, token),
          store: session.store,
          device: session.device,
          clock: clock,
        ).sync();
        await tasks.reload();
        next = SyncStatus(
          lastSynced: clock(),
          conflicts: (await session.store.readConflicts()).length,
        );
      }
    } on Exception catch (e) {
      if (!ref.mounted) return;
      next = SyncStatus(
        lastSynced: state.lastSynced,
        error: describeSyncError(e, session.repo),
        offline: isNetworkError(e),
        fixInSettings:
            e is GitHubException &&
            const {401, 403, 404}.contains(e.statusCode),
      );
    }
    if (ref.mounted) state = next;
  }
}

final syncProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);

/// [e], from syncing with [repo], as a sentence.
String describeSyncError(Object e, RepoRef repo) => switch (e) {
  _ when isNetworkError(e) =>
    'Couldn\'t reach GitHub. Changes are saved here and go out with the '
        'next sync.',
  GitHubException(statusCode: 401) =>
    'GitHub rejected the token. It may have expired.',
  GitHubException(statusCode: 403) =>
    'The token can\'t write to $repo. It needs Contents read and write.',
  GitHubException(statusCode: 404) => 'The token can\'t see $repo.',
  GitHubException(:final message) => 'GitHub said: $message.',
  SyncRetriesExhaustedException() =>
    'Other devices kept syncing at the same moment. Try again.',
  _ => '$e',
};
