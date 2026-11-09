import '../sync/conflict.dart';
import 'file_area.dart';
import 'sync_store.dart';

/// A [FileArea] in memory.
class MemoryArea implements FileArea {
  final Map<String, List<int>> files = {};

  @override
  Future<Map<String, List<int>>> readAll() async =>
      {for (final e in files.entries) e.key: List.of(e.value)};

  @override
  Future<void> write(String path, List<int> content) async =>
      files[checkRepoPath(path)] = List.of(content);

  @override
  Future<void> delete(String path) async => files.remove(path);
}

/// A [SyncStore] in memory, one per simulated device.
class MemoryStore implements SyncStore {
  @override
  final MemoryArea base = MemoryArea();

  @override
  final MemoryArea working = MemoryArea();

  String? baseCommit;
  List<SyncConflict> conflicts = [];

  @override
  Future<String?> readBaseCommit() async => baseCommit;

  @override
  Future<void> writeBaseCommit(String sha) async => baseCommit = sha;

  @override
  Future<List<SyncConflict>> readConflicts() async => List.of(conflicts);

  @override
  Future<void> writeConflicts(List<SyncConflict> conflicts) async =>
      this.conflicts = List.of(conflicts);
}
