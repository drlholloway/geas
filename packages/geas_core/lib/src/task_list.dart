import 'yaml_fields.dart';

/// The id of the built-in list that new tasks go to.
const inboxId = 'inbox';

final _idPattern = RegExp(r'^[A-Za-z0-9_-]+$');
const _keep = Object();

/// A list of tasks, stored as `lists/<id>.yaml`.
///
/// The inbox exists without a file; a `lists/inbox.yaml` only renames or
/// recolors it.
class TaskList {
  const TaskList({
    required this.id,
    required this.name,
    this.color,
    this.order = 0,
    this.source,
  });

  static const inbox = TaskList(id: inboxId, name: 'Inbox');

  /// Parses a list file, throwing [FormatException] if it isn't valid.
  factory TaskList.parse(String text) {
    const what = 'The list';
    final map = parseYamlMap(text, 'The list file');
    final id = requireString(map, 'id', what);
    if (!_idPattern.hasMatch(id)) {
      throw FormatException(
          'List id "$id" may only use A-Z, a-z, 0-9, _ and -.');
    }
    final order = map['order'];
    if (order != null && order is! int) {
      throw const FormatException('"order" in a list must be a whole number.');
    }
    return TaskList(
      id: id,
      name: requireString(map, 'name', what),
      color: optionalString(map, 'color', what),
      order: order as int? ?? 0,
      source: text,
    );
  }

  final String id;
  final String name;

  /// A CSS-style color such as `#4a90d9`, or null for the default.
  final String? color;

  /// Lists sort by [order], then name.
  final int order;

  /// The file as it was read, or null if it hasn't been written. [encode]
  /// edits it in place, keeping comments and unknown keys.
  final String? source;

  String encode() {
    final source = this.source;
    if (source == null || source.trim().isEmpty) return emitYamlMap(_fields());
    return patchYamlMap(source, _fields(), TaskList.parse(source)._fields());
  }

  Map<String, Object?> _fields() =>
      {'id': id, 'name': name, 'color': color, 'order': order};

  /// A copy with the given fields replaced. Pass null for [color] to clear it.
  TaskList copyWith({String? name, Object? color = _keep, int? order}) =>
      TaskList(
        id: id,
        name: name ?? this.name,
        color: identical(color, _keep) ? this.color : color as String?,
        order: order ?? this.order,
        source: source,
      );

  @override
  bool operator ==(Object other) =>
      other is TaskList &&
      other.id == id &&
      other.name == name &&
      other.color == color &&
      other.order == order;

  @override
  int get hashCode => Object.hash(id, name, color, order);

  @override
  String toString() => 'TaskList($id, $name)';
}

/// [lists] in display order, with the inbox first unless a file places it.
List<TaskList> withInbox(Iterable<TaskList> lists) {
  final sorted = lists.toList()
    ..sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
    });
  if (sorted.any((l) => l.id == inboxId)) return sorted;
  return [TaskList.inbox, ...sorted];
}

/// A new list called [name], ordered after [lists], with an id made from
/// the name that none of them has. Throws [FormatException] if the name has
/// no letter or digit, or a list already has it.
TaskList newList(String name, Iterable<TaskList> lists, {String? color}) {
  name = name.trim();
  final existing = withInbox(lists);
  if (existing.any((l) => l.name.toLowerCase() == name.toLowerCase())) {
    throw FormatException('There is already a list called "$name".');
  }
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.isEmpty) {
    throw const FormatException('A list name needs a letter or digit.');
  }
  var id = slug;
  for (var n = 2; existing.any((l) => l.id == id); n++) {
    id = '$slug-$n';
  }
  final order = existing.fold(0, (o, l) => l.order > o ? l.order : o) + 1;
  return TaskList(id: id, name: name, color: color, order: order);
}
