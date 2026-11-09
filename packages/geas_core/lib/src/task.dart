import 'dart:math';

import 'package:collection/collection.dart';
import 'package:yaml/yaml.dart';

import 'checklist.dart';
import 'due.dart';
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
    final match = _frontmatterPattern.matchAsPrefix(text);
    if (match == null) {
      throw const FormatException(
        'A task file starts with YAML frontmatter between "---" lines.',
      );
    }
    final frontmatter = match[1]!;
    return Task._fromYaml(
      parseYamlMap(frontmatter.isEmpty ? '{}' : frontmatter, 'Frontmatter'),
      body: text.substring(match.end),
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
    final yaml = source == null || source.trim().isEmpty
        ? emitYamlMap(fields)
        : patchYamlMap(
            source,
            fields,
            Task._fromYaml(parseYamlMap(source, 'Frontmatter'), body: '')
                ._fields(),
          );
    return '---\n$yaml---\n$body';
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

  /// A copy with the given fields replaced. Pass null for [due] or
  /// [completed] to clear them. Callers set [updated] on every edit.
  Task copyWith({
    String? title,
    String? list,
    List<String>? tags,
    Object? due = _keep,
    Priority? priority,
    DateTime? updated,
    Object? completed = _keep,
    String? body,
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
      other.body == body;

  @override
  int get hashCode => Object.hash(id, title, list, Object.hashAll(tags), due,
      priority, created, updated, completed, body);

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
