import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';

import 'session.dart';
import 'store.dart';

/// Conflicts sync resolved on its own and nobody has dismissed yet, newest
/// first. Sync refreshes it.
class ConflictsNotifier extends AsyncNotifier<List<SyncConflict>> {
  @override
  Future<List<SyncConflict>> build() async {
    final session = ref.watch(sessionProvider);
    if (session == null) return const [];
    final conflicts = await session.store.readConflicts();
    return conflicts.reversed.toList();
  }

  /// Forgets [conflict], keeping what sync kept.
  Future<void> dismiss(SyncConflict conflict) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final remaining = [
      for (final c in await session.store.readConflicts())
        if (!_same(c, conflict)) c,
    ];
    await session.store.writeConflicts(remaining);
    if (ref.mounted) state = AsyncData(remaining.reversed.toList());
  }

  /// Puts back the version sync set aside, or for an edit that won over a
  /// deletion, deletes it after all. Then dismisses [conflict].
  Future<void> useSetAside(SyncConflict conflict) async {
    final store = ref.read(taskStoreProvider.notifier);
    final text = conflict.setAside;
    if (text == null) {
      if (conflict.path.endsWith('.md')) {
        store.delete(conflict.key);
      } else {
        await store.restoreFile(conflict.path, null);
      }
    } else if (conflict.path.endsWith('.md')) {
      store.restoreTask(Task.parse(text));
    } else {
      await store.restoreFile(conflict.path, text);
    }
    await dismiss(conflict);
  }

  static bool _same(SyncConflict a, SyncConflict b) =>
      a.key == b.key &&
      a.detected.isAtSameMomentAs(b.detected) &&
      a.kind == b.kind;
}

final conflictsProvider =
    AsyncNotifierProvider<ConflictsNotifier, List<SyncConflict>>(
      ConflictsNotifier.new,
    );
