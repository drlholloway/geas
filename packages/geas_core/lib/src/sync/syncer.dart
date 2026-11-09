import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import '../github/git_hash.dart';
import '../github/github_client.dart';
import '../init.dart';
import '../repo_config.dart';
import '../store/file_area.dart';
import '../store/sync_store.dart';
import 'conflict.dart';
import 'merge.dart';

/// The data repo has no commits, or no `geas.yaml`.
class NotInitializedException implements Exception {
  const NotInitializedException(this.repo);

  final RepoRef repo;

  @override
  String toString() =>
      '$repo is not a Geas data repo yet. Run `geas init $repo`.';
}

/// Sync gave up because other devices kept pushing first.
class SyncRetriesExhaustedException implements Exception {
  const SyncRetriesExhaustedException(this.attempts);

  final int attempts;

  @override
  String toString() =>
      'Sync failed after $attempts attempts: other devices kept pushing '
      'first. Try again.';
}

/// What a sync did.
class SyncResult {
  const SyncResult({
    required this.commit,
    required this.pulled,
    required this.added,
    required this.updated,
    required this.moved,
    required this.removed,
    required this.conflicts,
  });

  /// The commit this device now matches.
  final String commit;

  /// Files that changed on the remote since the last sync.
  final int pulled;

  /// Files this sync's commit added, changed, moved and removed. All zero if
  /// there was nothing to push.
  final int added, updated, moved, removed;

  final List<SyncConflict> conflicts;

  bool get pushed => added + updated + moved + removed > 0;
}

/// Syncs one device's [store] with the data repo behind [github].
class Syncer {
  Syncer({
    required this.github,
    required this.store,
    required this.device,
    DateTime Function()? clock,
    this.maxAttempts = 4,
  }) : _clock = clock ?? DateTime.now;

  final GitHubClient github;
  final SyncStore store;

  /// Names this device in commit messages.
  final String device;
  final int maxAttempts;
  final DateTime Function() _clock;

  /// Pulls, merges and pushes. Nothing local changes unless the whole sync
  /// succeeds.
  Future<SyncResult> sync() async {
    for (var attempt = 1;; attempt++) {
      try {
        return await _attempt();
      } on NotFastForwardException {
        if (attempt >= maxAttempts) {
          throw SyncRetriesExhaustedException(attempt);
        }
      }
    }
  }

  Future<SyncResult> _attempt() async {
    final head = await github.branchHead();
    if (head == null) throw NotInitializedException(github.repo);
    final baseCommit = await store.readBaseCommit();
    final base = await store.base.readAll();
    final working = await store.working.readAll();
    final remoteTree = await github.commitTree(head);

    // The remote files, downloading only blobs that differ from base.
    var pulled = 0;
    final Map<String, List<int>> remote;
    if (head == baseCommit) {
      remote = base;
    } else {
      final shas = await github.readTree(remoteTree);
      remote = {};
      for (final MapEntry(key: path, value: sha) in shas.entries) {
        final known = base[path];
        if (known != null && gitBlobSha(known) == sha) {
          remote[path] = known;
        } else {
          remote[path] = await github.readBlob(sha);
          pulled++;
        }
      }
      pulled += base.keys.where((path) => !shas.containsKey(path)).length;
    }
    _checkConfig(remote);

    final now = _clock();
    final merge =
        mergeTrees(base: base, local: working, remote: remote, now: now);
    final changes = _diff(remote, merge.files);

    var commit = head;
    final counts = _count(remote, changes);
    if (changes.isNotEmpty) {
      final blobs = <String, String?>{};
      for (final MapEntry(key: path, value: content) in changes.entries) {
        blobs[path] = content == null ? null : await github.createBlob(content);
      }
      commit = await github.createCommit(
        message: _message(counts),
        tree: await github.createTree(remoteTree, blobs),
        parents: [head],
      );
      await github.updateBranch(commit);
    }

    await _persist(
      oldBase: base,
      workingSnapshot: working,
      merged: merge.files,
      commit: commit,
      conflicts: merge.conflicts,
    );
    return SyncResult(
      commit: commit,
      pulled: pulled,
      added: counts.added,
      updated: counts.updated,
      moved: counts.moved,
      removed: counts.removed,
      conflicts: merge.conflicts,
    );
  }

  void _checkConfig(Map<String, List<int>> remote) {
    final config = remote[repoConfigPath];
    if (config == null) throw NotInitializedException(github.repo);
    final format = RepoConfig.parse(utf8.decode(config)).format;
    if (format > currentFormat) throw UnsupportedFormatException(format);
  }

  /// Writes working, then base, then the base commit, so a crash part way
  /// leaves at worst local edits that equal the remote, which the next sync
  /// treats as no change.
  Future<void> _persist({
    required Map<String, List<int>> oldBase,
    required Map<String, List<int>> workingSnapshot,
    required Map<String, List<int>> merged,
    required String commit,
    required List<SyncConflict> conflicts,
  }) async {
    // Leave alone anything edited locally while the sync ran; the next sync
    // picks it up.
    final current = await store.working.readAll();
    for (final path in {...merged.keys, ...current.keys}) {
      if (!_bytesEqual.equals(current[path], workingSnapshot[path])) continue;
      await _put(store.working, path, current[path], merged[path]);
    }
    for (final path in {...merged.keys, ...oldBase.keys}) {
      await _put(store.base, path, oldBase[path], merged[path]);
    }
    await store.writeBaseCommit(commit);
    if (conflicts.isNotEmpty) {
      await store
          .writeConflicts([...await store.readConflicts(), ...conflicts]);
    }
  }

  String _message(_Counts c) {
    final parts = [
      if (c.updated > 0) '${c.updated} updated',
      if (c.added > 0) '${c.added} added',
      if (c.moved > 0) '${c.moved} moved',
      if (c.removed > 0) '${c.removed} removed',
    ];
    return 'sync($device): ${parts.join(', ')}';
  }
}

const _bytesEqual = ListEquality<int>();

/// Writes [to] over [from] at [path], or deletes it if [to] is null.
Future<void> _put(
  FileArea area,
  String path,
  List<int>? from,
  List<int>? to,
) async {
  if (_bytesEqual.equals(from, to)) return;
  if (to == null) {
    await area.delete(path);
  } else {
    await area.write(path, to);
  }
}

/// What turns [from] into [to]: new contents, or null for a deletion.
Map<String, List<int>?> _diff(
  Map<String, List<int>> from,
  Map<String, List<int>> to,
) =>
    {
      for (final path in {...from.keys, ...to.keys})
        if (!_bytesEqual.equals(from[path], to[path])) path: to[path],
    };

typedef _Counts = ({int added, int updated, int moved, int removed});

/// A file deleted in one place and added under the same name in another
/// (archiving) counts as moved.
_Counts _count(Map<String, List<int>> remote, Map<String, List<int>?> changes) {
  final added = <String>[], removed = <String>[];
  var updated = 0;
  changes.forEach((path, content) {
    if (content == null) {
      removed.add(path);
    } else if (remote.containsKey(path)) {
      updated++;
    } else {
      added.add(path);
    }
  });
  final removedNames = {for (final path in removed) p.posix.basename(path)};
  final moved = added
      .where((path) => removedNames.contains(p.posix.basename(path)))
      .length;
  return (
    added: added.length - moved,
    updated: updated,
    moved: moved,
    removed: removed.length - moved,
  );
}
