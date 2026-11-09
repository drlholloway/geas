/// How two versions of a file collided.
enum ConflictKind {
  /// Both sides changed the same field, or overlapping body lines, of a task
  /// or list.
  fields,

  /// One side edited it and the other deleted it. The edit was kept.
  editedAndDeleted,

  /// Both sides changed a file sync can't merge (one it can't parse, or one
  /// that isn't a task or list). The remote version was kept.
  file,
}

/// A conflict sync resolved on its own, kept so the conflicts view can show
/// what was set aside.
class SyncConflict {
  const SyncConflict({
    required this.key,
    required this.path,
    required this.kind,
    required this.detected,
    this.fields = const [],
    required this.keptLocal,
    this.setAside,
  });

  factory SyncConflict.fromJson(Map<String, Object?> json) => SyncConflict(
        key: json['key']! as String,
        path: json['path']! as String,
        kind: ConflictKind.values.byName(json['kind']! as String),
        detected: DateTime.parse(json['detected']! as String),
        fields: [
          for (final f in json['fields']! as List<Object?>) f! as String
        ],
        keptLocal: json['kept_local']! as bool,
        setAside: json['set_aside'] as String?,
      );

  /// The task id, or the path for anything that isn't a task.
  final String key;

  /// Where the kept version lives.
  final String path;
  final ConflictKind kind;
  final DateTime detected;

  /// For [ConflictKind.fields]: the frontmatter keys that collided, plus
  /// `body` if the notes did.
  final List<String> fields;

  /// Whether this device's version won. Tasks go to the side with the newer
  /// `updated`; everything else to the remote.
  final bool keptLocal;

  /// The full text of the losing version, or null if it was a deletion.
  final String? setAside;

  Map<String, Object?> toJson() => {
        'key': key,
        'path': path,
        'kind': kind.name,
        'detected': detected.toUtc().toIso8601String(),
        'fields': fields,
        'kept_local': keptLocal,
        'set_aside': setAside,
      };

  @override
  String toString() => 'SyncConflict(${kind.name}, $key, $fields)';
}
