import 'yaml_fields.dart';

final _idPattern = RegExp(r'^[A-Za-z0-9_-]+$');
const _keep = Object();

/// A named group of lists, saved filters and trackers, stored as
/// `folders/<id>.yaml`. What's in it is recorded on each member, as its
/// optional `folder` key, so moving one thing edits one file.
class Folder {
  const Folder({
    required this.id,
    required this.name,
    this.order = 0,
    this.parent,
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
      parent: switch (optionalString(map, 'parent', what)?.trim()) {
        null || '' => null,
        final id => id,
      },
      source: text,
    );
  }

  final String id;
  final String name;

  /// Folders sort by [order], then name, among those with the same parent.
  final int order;

  /// The id of the folder this one is inside: the optional `parent` key.
  /// Null at the top level. See [folderTree] for one that can't be honored.
  final String? parent;

  /// The file as it was read, or null if it hasn't been written. [encode]
  /// edits it in place, keeping comments and unknown keys.
  final String? source;

  String encode() {
    final source = this.source;
    if (source == null || source.trim().isEmpty) {
      // A top-level folder has no `parent` key.
      return emitYamlMap(
          _fields()..removeWhere((k, v) => k == 'parent' && v == null));
    }
    return patchYamlMap(source, _fields(), Folder.parse(source)._fields());
  }

  Map<String, Object?> _fields() =>
      {'id': id, 'name': name, 'order': order, 'parent': parent};

  /// A copy with the given fields replaced. Pass null for [parent] to move
  /// it to the top level.
  Folder copyWith({String? name, int? order, Object? parent = _keep}) => Folder(
        id: id,
        name: name ?? this.name,
        order: order ?? this.order,
        parent: identical(parent, _keep) ? this.parent : parent as String?,
        source: source,
      );

  @override
  bool operator ==(Object other) =>
      other is Folder &&
      other.id == id &&
      other.name == name &&
      other.order == order &&
      other.parent == parent;

  @override
  int get hashCode => Object.hash(id, name, order, parent);

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

/// The folder [folder] is really inside, among [folders]: its `parent`,
/// unless that names no folder, or following parents from there leads back
/// to [folder] (as two devices nesting a pair each way round can leave
/// it). Then it's at the top level, and this is null.
Folder? parentFolder(Folder folder, Iterable<Folder> folders) {
  final byId = {for (final f in folders) f.id: f};
  final parent = byId[folder.parent];
  final seen = {folder.id};
  for (var up = parent; up != null; up = byId[up.parent]) {
    if (!seen.add(up.id)) return null;
  }
  return parent;
}

/// [folders] as a tree, flattened: each folder followed by the folders
/// inside it, with how deep it is (0 at the top level). Siblings are in
/// display order.
List<({Folder folder, int depth})> folderTree(Iterable<Folder> folders) {
  final all = folders.toList();
  final children = <String?, List<Folder>>{};
  for (final folder in all) {
    (children[parentFolder(folder, all)?.id] ??= []).add(folder);
  }
  final tree = <({Folder folder, int depth})>[];
  void add(String? parent, int depth) {
    for (final folder in sortFolders(children[parent] ?? const [])) {
      tree.add((folder: folder, depth: depth));
      add(folder.id, depth + 1);
    }
  }

  add(null, 0);
  return tree;
}

/// The ids of every folder inside the folder [id], at any depth.
Set<String> foldersInside(String id, Iterable<Folder> folders) {
  final tree = folderTree(folders);
  final start = tree.indexWhere((n) => n.folder.id == id);
  if (start < 0) return const {};
  return {
    for (final node
        in tree.skip(start + 1).takeWhile((n) => n.depth > tree[start].depth))
      node.folder.id,
  };
}

/// A folder's name with the names of the folders it's inside, outermost
/// first: `Health / Diabetes`.
String folderPathName(Folder folder, Iterable<Folder> folders) {
  final names = [folder.name];
  for (var up = parentFolder(folder, folders);
      up != null;
      up = parentFolder(up, folders)) {
    names.insert(0, up.name);
  }
  return names.join(' / ');
}

/// [sequence] numbered in that order: the folders whose `order` has to
/// change for it, renumbered from 1.
List<Folder> renumberFolders(List<Folder> sequence) => [
      for (final (i, f) in sequence.indexed)
        if (f.order != i + 1) f.copyWith(order: i + 1),
    ];

/// A new folder called [name], after [folders], with an id made from the
/// name that none of them has. Throws [FormatException] if the name has no
/// letter or digit, or a folder already has it.
Folder newFolder(String name, Iterable<Folder> folders, {String? parent}) {
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
  return Folder(id: id, name: name, order: order, parent: parent);
}
