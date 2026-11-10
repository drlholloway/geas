import 'dart:math';

import 'package:collection/collection.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import 'checklist.dart';
import 'due.dart';
import 'order.dart';
import 'priority.dart';
import 'task_list.dart';
import 'ulid.dart';
import 'yaml_fields.dart';

final _idPattern = RegExp(r'^[A-Za-z0-9_-]+$');
final _frontmatterPattern = RegExp(
  r'^---[ \t]*\r?\n([\s\S]*?)^---[ \t]*(?:\r?\n|$)',
  multiLine: true,
);
const _keep = Object();

/// The YAML between the opening and closing `---` lines, and everything
/// after them, or null if [text] doesn't start with frontmatter.
({String frontmatter, String body})? splitFrontmatter(String text) {
  final match = _frontmatterPattern.matchAsPrefix(text);
  if (match == null) return null;
  return (frontmatter: match[1]!, body: text.substring(match.end));
}

/// One task: a Markdown file with YAML frontmatter, `tasks/<id>.md`.
class Task {
  Task({
    required this.id,
    required this.title,
    this.list = inboxId,
    List<String> tags = const [],
    this.due,
    this.priority = Priority.none,
    required DateTime created,
    required DateTime updated,
    DateTime? completed,
    this.body = '',
    this.order,
    this.frontmatter,
  })  : tags = List.unmodifiable(tags),
        created = _toSecond(created),
        updated = _toSecond(updated),
        completed = completed == null ? null : _toSecond(completed);

  /// A new task with a fresh ULID, created and updated [now].
  factory Task.create({
    required String title,
    required DateTime now,
    String list = inboxId,
    List<String> tags = const [],
    Due? due,
    Priority priority = Priority.none,
    String body = '',
    Random? random,
  }) =>
      Task(
        id: newUlid(now: now, random: random),
        title: title,
        list: list,
        tags: tags,
        due: due,
        priority: priority,
        created: now,
        updated: now,
        body: body,
      );

  /// Parses a task file, throwing [FormatException] if it isn't valid.
  factory Task.parse(String text) {
    final parts = splitFrontmatter(text);
    if (parts == null) {
      throw const FormatException(
        'A task file starts with YAML frontmatter between "---" lines.',
      );
    }
    final (:frontmatter, :body) = parts;
    return Task._fromYaml(
      parseYamlMap(frontmatter.isEmpty ? '{}' : frontmatter, 'Frontmatter'),
      body: body,
      frontmatter: frontmatter,
    );
  }

  factory Task._fromYaml(
    YamlMap map, {
    required String body,
    String? frontmatter,
  }) {
    const what = 'The task';
    final id = requireString(map, 'id', what);
    if (!_idPattern.hasMatch(id)) {
      throw FormatException(
          'Task id "$id" may only use A-Z, a-z, 0-9, _ and -.');
    }
    final due = optionalString(map, 'due', what);
    final priority = optionalString(map, 'priority', what);
    final completed = optionalString(map, 'completed', what);
    return Task(
      id: id,
      title: requireString(map, 'title', what),
      list: optionalString(map, 'list', what) ?? inboxId,
      tags: _parseTags(map['tags']),
      due: due == null ? null : Due.parse(due),
      priority: priority == null ? Priority.none : Priority.parse(priority),
      created: _parseTimestamp(requireString(map, 'created', what), 'created'),
      updated: _parseTimestamp(requireString(map, 'updated', what), 'updated'),
      completed:
          completed == null ? null : _parseTimestamp(completed, 'completed'),
      body: body,
      order: map['order'] == null ? null : Order.parse(map['order']),
      frontmatter: frontmatter,
    );
  }

  /// The ULID, which is also the filename.
  final String id;
  final String title;

  /// The id of the list it's in.
  final String list;
  final List<String> tags;
  final Due? due;
  final Priority priority;

  /// UTC, to the second.
  final DateTime created;

  /// UTC, to the second. Merges keep the side with the newer `updated`.
  final DateTime updated;

  /// UTC, to the second; null while open.
  final DateTime? completed;

  /// Notes and checklist, as Markdown.
  final String body;

  /// The order this task tracks, if any: the optional `order` map.
  final Order? order;

  /// The frontmatter as it was read, or null for a task that hasn't been
  /// written yet. [encode] edits it in place, so comments, formatting and
  /// keys Geas doesn't know about survive.
  final String? frontmatter;

  bool get isCompleted => completed != null;

  /// The Markdown checkboxes in [body].
  List<ChecklistItem> get checklist => parseChecklist(body);

  /// This task as a file. A parsed task changes only the fields that differ
  /// from what was read; a new one is written in the canonical layout.
  String encode() {
    final fields = _fields();
    final source = frontmatter;
    final fresh = source == null || source.trim().isEmpty;
    final read = fresh
        ? null
        : Task._fromYaml(parseYamlMap(source, 'Frontmatter'), body: '');
    var yaml = fresh
        ? emitYamlMap(fields)
        : patchYamlMap(source, fields, read!._fields());
    if (order != read?.order) yaml = _patchOrder(yaml, read?.order);
    return '---\n$yaml---\n$body';
  }

  /// [yaml] with the `order` map set to [order], changing only the keys
  /// that differ from [previous], or removed if [order] is null. Optional,
  /// so a task without one has no `order` key at all.
  String _patchOrder(String yaml, Order? previous) {
    final editor = YamlEditor(yaml);
    final order = this.order;
    if (order == null) {
      editor.remove(['order']);
    } else if (previous == null) {
      editor.update(['order'], order.toYaml());
    } else {
      final now = order.toYaml(), before = previous.toYaml();
      for (final key in {...before.keys, ...now.keys}) {
        if (const DeepCollectionEquality().equals(now[key], before[key])) {
          continue;
        }
        if (!now.containsKey(key)) {
          editor.remove(['order', key]);
        } else {
          editor.update(['order', key], now[key]);
        }
      }
    }
    final text = editor.toString();
    return text.endsWith('\n') ? text : '$text\n';
  }

  Map<String, Object?> _fields() => {
        'id': id,
        'title': title,
        'list': list,
        'tags': tags,
        'due': due?.toString(),
        'priority': priority.name,
        'created': _formatTimestamp(created),
        'updated': _formatTimestamp(updated),
        'completed': completed == null ? null : _formatTimestamp(completed!),
      };

  /// A copy with the given fields replaced. Pass null for [due],
  /// [completed] or [order] to clear them. Callers set [updated] on every edit.
  Task copyWith({
    String? title,
    String? list,
    List<String>? tags,
    Object? due = _keep,
    Priority? priority,
    DateTime? updated,
    Object? completed = _keep,
    String? body,
    Object? order = _keep,
  }) =>
      Task(
        id: id,
        title: title ?? this.title,
        list: list ?? this.list,
        tags: tags ?? this.tags,
        due: identical(due, _keep) ? this.due : due as Due?,
        priority: priority ?? this.priority,
        created: created,
        updated: updated ?? this.updated,
        completed: identical(completed, _keep)
            ? this.completed
            : completed as DateTime?,
        body: body ?? this.body,
        order: identical(order, _keep) ? this.order : order as Order?,
        frontmatter: frontmatter,
      );

  /// Marks it done at [now].
  Task complete(DateTime now) => copyWith(completed: now, updated: now);

  /// Marks it open again at [now].
  Task reopen(DateTime now) => copyWith(completed: null, updated: now);

  /// Checks or unchecks the checklist item on body line [line] at [now].
  Task setChecklistItem(int line,
          {required bool done, required DateTime now}) =>
      copyWith(body: setChecklistLine(body, line, done: done), updated: now);

  /// Equal fields; [frontmatter] isn't compared.
  @override
  bool operator ==(Object other) =>
      other is Task &&
      other.id == id &&
      other.title == title &&
      other.list == list &&
      const ListEquality<String>().equals(other.tags, tags) &&
      other.due == due &&
      other.priority == priority &&
      other.created == created &&
      other.updated == updated &&
      other.completed == completed &&
      other.body == body &&
      other.order == order;

  @override
  int get hashCode => Object.hash(id, title, list, Object.hashAll(tags), due,
      priority, created, updated, completed, body, order);

  @override
  String toString() => 'Task($id, $title)';
}

List<String> _parseTags(Object? value) => switch (value) {
      null => const [],
      YamlList() => [
          for (final tag in value)
            if (tag is YamlMap || tag is YamlList)
              throw const FormatException('Each tag must be a single word.')
            else if (tag != null)
              '$tag',
        ],
      YamlMap() => throw const FormatException('"tags" must be a list.'),
      _ => ['$value'],
    };

DateTime _parseTimestamp(String text, String key) {
  final parsed = DateTime.tryParse(text);
  if (parsed == null) {
    throw FormatException('"$key" must be a timestamp, got "$text".');
  }
  return parsed.toUtc();
}

String _formatTimestamp(DateTime time) =>
    '${time.toUtc().toIso8601String().substring(0, 19)}Z';

DateTime _toSecond(DateTime time) {
  final utc = time.toUtc();
  return DateTime.utc(
      utc.year, utc.month, utc.day, utc.hour, utc.minute, utc.second);
}
