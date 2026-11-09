import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../sync/conflict.dart';
import 'file_area.dart';

/// Everything a device keeps between syncs.
abstract interface class SyncStore {
  /// The data repo as of the last successful sync.
  FileArea get base;

  /// [base] plus this device's edits since. The app and CLI read and write
  /// here; only sync touches [base].
  FileArea get working;

  /// The commit [base] matches, or null before the first sync.
  Future<String?> readBaseCommit();

  Future<void> writeBaseCommit(String sha);

  /// Conflicts sync has resolved but not yet shown or dismissed.
  Future<List<SyncConflict>> readConflicts();

  Future<void> writeConflicts(List<SyncConflict> conflicts);
}

/// A [SyncStore] in a directory:
///
/// ```
/// <root>/base/        files as of the last sync
/// <root>/working/     base plus local edits
/// <root>/sync.json    {"base_commit": "<sha>"}
/// <root>/conflicts.json
/// ```
class DirectoryStore implements SyncStore {
  DirectoryStore(this.root)
      : base = DirectoryArea(p.join(root, 'base')),
        working = DirectoryArea(p.join(root, 'working')),
        _meta = DirectoryArea(root);

  final String root;

  @override
  final DirectoryArea base;

  @override
  final DirectoryArea working;

  /// The root itself, for writing the JSON files atomically.
  final DirectoryArea _meta;

  @override
  Future<String?> readBaseCommit() async {
    final json = await _readJson('sync.json');
    return json is Map ? json['base_commit'] as String? : null;
  }

  @override
  Future<void> writeBaseCommit(String sha) =>
      _writeJson('sync.json', {'base_commit': sha});

  @override
  Future<List<SyncConflict>> readConflicts() async {
    final json = await _readJson('conflicts.json');
    if (json is! List) return [];
    return [
      for (final item in json)
        SyncConflict.fromJson(item as Map<String, Object?>),
    ];
  }

  @override
  Future<void> writeConflicts(List<SyncConflict> conflicts) =>
      _writeJson('conflicts.json', [for (final c in conflicts) c.toJson()]);

  Future<Object?> _readJson(String name) async {
    final file = File(p.join(root, name));
    if (!await file.exists()) return null;
    return jsonDecode(await file.readAsString());
  }

  Future<void> _writeJson(String name, Object json) => _meta.write(
      name, utf8.encode(const JsonEncoder.withIndent('  ').convert(json)));
}
