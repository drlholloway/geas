import 'yaml_fields.dart';

final _idPattern = RegExp(r'^[A-Za-z0-9_-]+$');

/// A named group of lists, saved filters and trackers, stored as
/// `folders/<id>.yaml`. What's in it is recorded on each member, as its
/// optional `folder` key, so moving one thing edits one file.
class Folder {
  const Folder({
    required this.id,
    required this.name,
    this.order = 0,
    this.source,
  });

  /// Parses a folder file, throwing [FormatException] if it isn't valid.
  factory Folder.parse(String text) {
    const what = 'The folder';
    final map = parseYamlMap(text, 'The folder file');
    final id = requireString(map, 'id', what);
    if (!_idPattern.hasMatch(id)) {
      throw FormatException(
          'Folder id "$id" may only use A-Z, a-z, 0-9, _ and -.');
    }
    final order = map['order'];
    if (order != null && order is! int) {
      throw const FormatException(
          '"order" in a folder must be a whole number.');
    }
    return Folder(
      id: id,
      name: requireString(map, 'name', what),
      order: order as int? ?? 0,
      source: text,
    );
  }

  final String id;
  final String name;

  /// Folders sort by [order], then name.
  final int order;

  /// The file as it was read, or null if it hasn't been written. [encode]
  /// edits it in place, keeping comments and unknown keys.
  final String? source;

  String encode() {
    final source = this.source;
    if (source == null || source.trim().isEmpty) return emitYamlMap(_fields());
    return patchYamlMap(source, _fields(), Folder.parse(source)._fields());
  }

  Map<String, Object?> _fields() => {'id': id, 'name': name, 'order': order};

  Folder copyWith({String? name, int? order}) => Folder(
        id: id,
        name: name ?? this.name,
        order: order ?? this.order,
        source: source,
      );

  @override
  bool operator ==(Object other) =>
      other is Folder &&
      other.id == id &&
      other.name == name &&
      other.order == order;

  @override
  int get hashCode => Object.hash(id, name, order);

  @override
  String toString() => 'Folder($id, $name)';
}

/// Where the folder with [id] is stored.
String folderPath(String id) => 'folders/$id.yaml';

/// Whether [path] is where a folder file goes.
bool isFolderPath(String path) =>
    path.startsWith('folders/') && path.endsWith('.yaml');

/// [folders] in display order.
List<Folder> sortFolders(Iterable<Folder> folders) => folders.toList()
  ..sort((a, b) {
    final byOrder = a.order.compareTo(b.order);
    return byOrder != 0
        ? byOrder
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

/// A new folder called [name], after [folders], with an id made from the
/// name that none of them has. Throws [FormatException] if the name has no
/// letter or digit, or a folder already has it.
Folder newFolder(String name, Iterable<Folder> folders) {
  name = name.trim();
  if (folders.any((f) => f.name.toLowerCase() == name.toLowerCase())) {
    throw FormatException('There is already a folder called "$name".');
  }
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.isEmpty) {
    throw const FormatException('A folder name needs a letter or digit.');
  }
  var id = slug;
  for (var n = 2; folders.any((f) => f.id == id); n++) {
    id = '$slug-$n';
  }
  final order = folders.fold(0, (o, f) => f.order > o ? f.order : o) + 1;
  return Folder(id: id, name: name, order: order);
}
