import 'local_date.dart';
import 'priority.dart';
import 'queries.dart';
import 'task.dart';
import 'task_list.dart';
import 'yaml_fields.dart';

/// Which tasks a [TaskQuery] looks at by whether they're done.
enum QueryStatus { open, done, all }

/// When a [TaskQuery] wants tasks due.
enum QueryDue {
  /// Due today, or overdue.
  today,

  /// Due in the next 7 days, or overdue.
  week,
  overdue,

  /// With no due date.
  none,

  /// With any due date.
  any,
}

/// A search over tasks, typed as one line:
///
/// - plain words must all appear in the title or notes, ignoring case;
/// - `#tag` must be one of its tags;
/// - `^list` must be its list, by id or name (with `-` for spaces);
/// - `!high`, `!med`, `!low` or `!none` must be its priority;
/// - `due:today`, `due:week`, `due:overdue`, `due:none` or `due:any`;
/// - `is:done` or `is:all`, instead of open tasks only.
///
/// Several tags, or several lists, match a task with any of them. A `^`
/// or `due:` word that names nothing matches no task.
class TaskQuery {
  const TaskQuery({
    this.words = const [],
    this.tags = const [],
    this.lists = const [],
    this.priority,
    this.due,
    this.status = QueryStatus.open,
    this.impossible = false,
  });

  /// Parses [text]; [lists] are what `^list` words can name.
  factory TaskQuery.parse(String text, {Iterable<TaskList> lists = const []}) {
    final words = <String>[], tags = <String>[], ids = <String>[];
    Priority? priority;
    QueryDue? due;
    var status = QueryStatus.open;
    var impossible = false;
    for (final word in text.trim().split(RegExp(r'\s+'))) {
      final lower = word.toLowerCase();
      if (word.isEmpty) continue;
      if (word.startsWith('#') && word.length > 1) {
        tags.add(lower.substring(1));
      } else if (word.startsWith('^') && word.length > 1) {
        final wanted = lower.substring(1);
        final found = withInbox(lists).where((l) =>
            l.id.toLowerCase() == wanted ||
            l.name.toLowerCase().replaceAll(RegExp(r'\s+'), '-') == wanted);
        found.isEmpty ? impossible = true : ids.add(found.first.id);
      } else if (_priorities[lower] case final p?) {
        priority = p;
      } else if (lower.startsWith('due:')) {
        final named =
            QueryDue.values.where((d) => d.name == lower.substring(4));
        named.isEmpty ? impossible = true : due = named.first;
      } else if (lower == 'is:done') {
        status = QueryStatus.done;
      } else if (lower == 'is:all') {
        status = QueryStatus.all;
      } else if (lower == 'is:open') {
        status = QueryStatus.open;
      } else {
        words.add(lower);
      }
    }
    return TaskQuery(
      words: words,
      tags: tags,
      lists: ids,
      priority: priority,
      due: due,
      status: status,
      impossible: impossible,
    );
  }

  static const _priorities = {
    '!high': Priority.high,
    '!h': Priority.high,
    '!medium': Priority.medium,
    '!med': Priority.medium,
    '!m': Priority.medium,
    '!low': Priority.low,
    '!l': Priority.low,
    '!none': Priority.none,
  };

  /// Lowercase; each must be in the title or notes.
  final List<String> words;

  /// Lowercase; a task needs one of them.
  final List<String> tags;

  /// List ids; a task needs to be in one of them.
  final List<String> lists;
  final Priority? priority;
  final QueryDue? due;
  final QueryStatus status;

  /// It named a list or due window that doesn't exist, so nothing matches.
  final bool impossible;

  /// Nothing was asked for: no words and no filters.
  bool get isEmpty =>
      words.isEmpty &&
      tags.isEmpty &&
      lists.isEmpty &&
      priority == null &&
      due == null &&
      status == QueryStatus.open &&
      !impossible;

  bool matches(Task task, DateTime now) {
    if (impossible) return false;
    if (status == QueryStatus.open && task.isCompleted) return false;
    if (status == QueryStatus.done && !task.isCompleted) return false;
    if (lists.isNotEmpty && !lists.contains(task.list)) return false;
    if (priority != null && task.priority != priority) return false;
    if (tags.isNotEmpty &&
        !task.tags.any((t) => tags.contains(t.toLowerCase()))) {
      return false;
    }
    if (due != null && !_dueMatches(task, now)) return false;
    if (words.isEmpty) return true;
    final text = '${task.title}\n${task.body}'.toLowerCase();
    return words.every(text.contains);
  }

  bool _dueMatches(Task task, DateTime now) {
    if (due == QueryDue.none) return task.due == null;
    if (task.due == null) return false;
    if (due == QueryDue.any) return true;
    final bucket = dueBucket(task, now);
    return switch (due!) {
      QueryDue.overdue => bucket == DueBucket.overdue,
      QueryDue.today =>
        bucket == DueBucket.overdue || bucket == DueBucket.today,
      _ => bucket == DueBucket.overdue ||
          bucket == DueBucket.today ||
          task.due!.localDate.isBefore(LocalDate.of(now.toLocal()).addDays(7)),
    };
  }

  /// The [tasks] that match: open ones first in the usual order, then
  /// finished ones, most recently done first.
  List<Task> search(Iterable<Task> tasks, DateTime now) {
    final found = tasks.where((t) => matches(t, now)).toList();
    return [
      ...found.where((t) => !t.isCompleted).toList()..sort(compareByDue),
      ...found.where((t) => t.isCompleted).toList()
        ..sort((a, b) => b.completed!.compareTo(a.completed!)),
    ];
  }
}

final _idPattern = RegExp(r'^[A-Za-z0-9_-]+$');
const _keepFolder = Object();

/// A search kept under a name, stored as `filters/<id>.yaml` so every
/// device has it.
class SavedFilter {
  const SavedFilter({
    required this.id,
    required this.name,
    required this.query,
    this.order = 0,
    this.folder,
    this.source,
  });

  /// Parses a filter file, throwing [FormatException] if it isn't valid.
  factory SavedFilter.parse(String text) {
    const what = 'The filter';
    final map = parseYamlMap(text, 'The filter file');
    final id = requireString(map, 'id', what);
    if (!_idPattern.hasMatch(id)) {
      throw FormatException(
          'Filter id "$id" may only use A-Z, a-z, 0-9, _ and -.');
    }
    final order = map['order'];
    if (order != null && order is! int) {
      throw const FormatException(
          '"order" in a filter must be a whole number.');
    }
    return SavedFilter(
      id: id,
      name: requireString(map, 'name', what),
      query: optionalString(map, 'query', what) ?? '',
      order: order as int? ?? 0,
      folder: switch (optionalString(map, 'folder', what)?.trim()) {
        null || '' => null,
        final id => id,
      },
      source: text,
    );
  }

  final String id;
  final String name;

  /// As typed; read with [TaskQuery.parse].
  final String query;

  /// Filters sort by [order], then name.
  final int order;

  /// The id of the folder it's in: the optional `folder` key.
  final String? folder;

  /// The file as it was read, or null if it hasn't been written. [encode]
  /// edits it in place, keeping comments and unknown keys.
  final String? source;

  String encode() {
    final source = this.source;
    if (source == null || source.trim().isEmpty) {
      // A filter in no folder has no `folder` key.
      return emitYamlMap(
          _fields()..removeWhere((k, v) => k == 'folder' && v == null));
    }
    return patchYamlMap(source, _fields(), SavedFilter.parse(source)._fields());
  }

  Map<String, Object?> _fields() => {
        'id': id,
        'name': name,
        'query': query,
        'order': order,
        'folder': folder,
      };

  /// A copy with the given fields replaced. Pass null for [folder] to take
  /// it out of its folder.
  SavedFilter copyWith({
    String? name,
    String? query,
    int? order,
    Object? folder = _keepFolder,
  }) =>
      SavedFilter(
        id: id,
        name: name ?? this.name,
        query: query ?? this.query,
        order: order ?? this.order,
        folder:
            identical(folder, _keepFolder) ? this.folder : folder as String?,
        source: source,
      );

  @override
  bool operator ==(Object other) =>
      other is SavedFilter &&
      other.id == id &&
      other.name == name &&
      other.query == query &&
      other.order == order &&
      other.folder == folder;

  @override
  int get hashCode => Object.hash(id, name, query, order, folder);

  @override
  String toString() => 'SavedFilter($id, $query)';
}

/// Where the filter with [id] is stored.
String filterPath(String id) => 'filters/$id.yaml';

/// Whether [path] is where a saved filter goes.
bool isFilterPath(String path) =>
    path.startsWith('filters/') && path.endsWith('.yaml');

/// [filters] in display order.
List<SavedFilter> sortFilters(Iterable<SavedFilter> filters) => filters.toList()
  ..sort((a, b) {
    final byOrder = a.order.compareTo(b.order);
    return byOrder != 0
        ? byOrder
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

/// A new filter called [name] for [query], after [filters], with an id made
/// from the name that none of them has. Throws [FormatException] if the
/// name has no letter or digit, or a filter already has it.
SavedFilter newFilter(
    String name, String query, Iterable<SavedFilter> filters) {
  name = name.trim();
  if (filters.any((f) => f.name.toLowerCase() == name.toLowerCase())) {
    throw FormatException('There is already a filter called "$name".');
  }
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.isEmpty) {
    throw const FormatException('A filter name needs a letter or digit.');
  }
  var id = slug;
  for (var n = 2; filters.any((f) => f.id == id); n++) {
    id = '$slug-$n';
  }
  final order = filters.fold(0, (o, f) => f.order > o ? f.order : o) + 1;
  return SavedFilter(id: id, name: name, query: query.trim(), order: order);
}
