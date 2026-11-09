import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../archive.dart';
import '../task.dart';
import '../task_list.dart';
import 'conflict.dart';
import 'line_merge.dart';

/// The result of [mergeTrees].
class TreeMerge {
  const TreeMerge(this.files, this.conflicts);

  /// The merged data repo, by path.
  final Map<String, List<int>> files;
  final List<SyncConflict> conflicts;
}

/// Merges this device's [local] files with [remote] against their common
/// [base], all keyed by path.
///
/// Tasks are matched by id, not path, so archiving on one side and editing
/// on the other still merges. Then:
///
/// - Changed on one side only: that side wins.
/// - Changed on both: frontmatter merges key by key, unknown keys included,
///   and the body merges line by line. Where both changed the same key or
///   lines, the side with the newer `updated` wins and the conflict is
///   recorded. `updated` becomes the later of the two.
/// - Edited on one side and deleted on the other: the edit is kept and
///   recorded.
/// - Lists merge key by key, with the remote winning a conflict. Anything
///   else changed on both sides keeps the remote and records the local.
///
/// Every task in the result is moved to where [taskPath] says it belongs at
/// [now], which is how completed tasks get archived.
TreeMerge mergeTrees({
  required Map<String, List<int>> base,
  required Map<String, List<int>> local,
  required Map<String, List<int>> remote,
  required DateTime now,
}) {
  final b = _index(base), l = _index(local), r = _index(remote);
  final files = <String, List<int>>{};
  final conflicts = <SyncConflict>[];

  for (final key in {...r.keys, ...l.keys, ...b.keys}) {
    final eb = b[key], el = l[key], er = r[key];
    final _Entry? kept;
    if (_same(el, eb)) {
      kept = er;
    } else if (_same(er, eb) || _same(el, er)) {
      kept = el;
    } else if (el == null || er == null) {
      kept = el ?? er;
      conflicts.add(SyncConflict(
        key: kept!.key,
        path: kept.path,
        kind: ConflictKind.editedAndDeleted,
        detected: now,
        keptLocal: el != null,
      ));
    } else if (el.task != null && er.task != null) {
      kept = _mergeTask(eb?.task == null ? null : eb, el, er, now, conflicts);
    } else if (el.isList && er.isList) {
      kept =
          _mergeList((eb?.isList ?? false) ? eb : null, el, er, now, conflicts);
    } else {
      kept = er;
      conflicts.add(_fileConflict(er, setAside: el, now: now));
    }
    if (kept == null) continue;
    final task = kept.task;
    files[task == null ? kept.path : taskPath(task, now)] = kept.bytes;
  }
  return TreeMerge(files, conflicts);
}

class _Entry {
  _Entry(this.path, this.bytes, {this.task, this.isList = false});

  final String path;
  final List<int> bytes;

  /// Parsed, for a valid task file.
  final Task? task;

  /// A valid list file.
  final bool isList;

  String get key => task?.id ?? path;
  String get text => utf8.decode(bytes, allowMalformed: true);
}

Map<String, _Entry> _index(Map<String, List<int>> files) {
  final entries = <String, _Entry>{};
  files.forEach((path, bytes) {
    final entry = _entry(path, bytes);
    entries[entry.task == null ? 'path:$path' : 'task:${entry.task!.id}'] =
        entry;
  });
  return entries;
}

_Entry _entry(String path, List<int> bytes) {
  try {
    if ((path.startsWith('tasks/') || path.startsWith('archive/')) &&
        path.endsWith('.md')) {
      return _Entry(path, bytes, task: Task.parse(utf8.decode(bytes)));
    }
    if (path.startsWith('lists/') && path.endsWith('.yaml')) {
      TaskList.parse(utf8.decode(bytes));
      return _Entry(path, bytes, isList: true);
    }
  } on FormatException {
    // Hand-edited into something invalid: merge it as an opaque file.
  }
  return _Entry(path, bytes);
}

const _bytesEqual = ListEquality<int>();

bool _same(_Entry? x, _Entry? y) {
  if (x == null || y == null) return x == y;
  return x.path == y.path && _bytesEqual.equals(x.bytes, y.bytes);
}

_Entry _mergeTask(
  _Entry? base,
  _Entry local,
  _Entry remote,
  DateTime now,
  List<SyncConflict> conflicts,
) {
  final localWins = local.task!.updated.isAfter(remote.task!.updated);
  final bp = base == null ? null : splitFrontmatter(base.text);
  final lp = splitFrontmatter(local.text)!, rp = splitFrontmatter(remote.text)!;
  final newer = localWins ? lp.frontmatter : rp.frontmatter;

  final frontmatter = _mergeYaml(
    bp?.frontmatter,
    lp.frontmatter,
    rp.frontmatter,
    localWins: localWins,
    // Both sides bump `updated` on every edit, so it always differs.
    overrides: {'updated': _plainMap(newer)['updated']},
  );
  final fields = [...frontmatter.conflicts];
  final body = mergeLines(bp?.body ?? '', lp.body, rp.body);
  if (body.conflict) fields.add('body');
  final text = '---\n${frontmatter.text}---\n'
      '${body.text ?? (localWins ? lp.body : rp.body)}';
  final winner = localWins ? local : remote, loser = localWins ? remote : local;

  final Task task;
  try {
    task = Task.parse(text);
  } on FormatException {
    // The combination doesn't parse; keep the newer version whole.
    conflicts.add(SyncConflict(
      key: winner.key,
      path: winner.path,
      kind: ConflictKind.fields,
      detected: now,
      fields: const ['frontmatter'],
      keptLocal: localWins,
      setAside: loser.text,
    ));
    return winner;
  }
  if (fields.isNotEmpty) {
    conflicts.add(SyncConflict(
      key: task.id,
      path: taskPath(task, now),
      kind: ConflictKind.fields,
      detected: now,
      fields: fields,
      keptLocal: localWins,
      setAside: loser.text,
    ));
  }
  return _Entry(remote.path, utf8.encode(text), task: task);
}

_Entry _mergeList(
  _Entry? base,
  _Entry local,
  _Entry remote,
  DateTime now,
  List<SyncConflict> conflicts,
) {
  final merged =
      _mergeYaml(base?.text, local.text, remote.text, localWins: false);
  try {
    TaskList.parse(merged.text);
  } on FormatException {
    conflicts.add(_fileConflict(remote, setAside: local, now: now));
    return remote;
  }
  if (merged.conflicts.isNotEmpty) {
    conflicts.add(SyncConflict(
      key: remote.path,
      path: remote.path,
      kind: ConflictKind.fields,
      detected: now,
      fields: merged.conflicts,
      keptLocal: false,
      setAside: local.text,
    ));
  }
  return _Entry(remote.path, utf8.encode(merged.text), isList: true);
}

SyncConflict _fileConflict(
  _Entry kept, {
  required _Entry setAside,
  required DateTime now,
}) =>
    SyncConflict(
      key: kept.key,
      path: kept.path,
      kind: ConflictKind.file,
      detected: now,
      keptLocal: false,
      setAside: setAside.text,
    );

const _absent = Object();
const _deepEqual = DeepCollectionEquality();

bool _eq(Object? x, Object? y) {
  if (identical(x, _absent) || identical(y, _absent)) return identical(x, y);
  return _deepEqual.equals(x, y);
}

/// Three-way merge of YAML maps, key by key, written as an edit of [remote]
/// so its comments and layout survive. [overrides] set keys outright.
({String text, List<String> conflicts}) _mergeYaml(
  String? base,
  String local,
  String remote, {
  required bool localWins,
  Map<String, Object?> overrides = const {},
}) {
  final bm = base == null ? const <String, Object?>{} : _plainMap(base);
  final lm = _plainMap(local), rm = _plainMap(remote);
  final editor = YamlEditor(remote.trim().isEmpty ? '{}' : remote);
  final conflicts = <String>[];

  for (final key in {...rm.keys, ...lm.keys, ...bm.keys}) {
    final bv = bm.containsKey(key) ? bm[key] : _absent;
    final lv = lm.containsKey(key) ? lm[key] : _absent;
    final rv = rm.containsKey(key) ? rm[key] : _absent;
    final Object? merged;
    if (overrides.containsKey(key)) {
      merged = overrides[key];
    } else if (_eq(lv, rv) || _eq(rv, bv)) {
      merged = lv;
    } else if (_eq(lv, bv)) {
      merged = rv;
    } else {
      merged = localWins ? lv : rv;
      conflicts.add(key);
    }
    if (_eq(merged, rv)) continue;
    if (identical(merged, _absent)) {
      editor.remove([key]);
    } else {
      editor.update([key], _wrap(merged));
    }
  }
  final text = editor.toString();
  return (text: text.endsWith('\n') ? text : '$text\n', conflicts: conflicts);
}

/// Lists of scalars in flow style (`[a, b]`), as Geas writes tags.
Object? _wrap(Object? value) =>
    value is List && value.every((v) => v is! List && v is! Map)
        ? wrapAsYamlNode(value, collectionStyle: CollectionStyle.FLOW)
        : value;

Map<String, Object?> _plainMap(String text) {
  if (text.trim().isEmpty) return {};
  final doc = loadYaml(text);
  if (doc is! YamlMap) return {};
  return {for (final e in doc.entries) '${e.key}': _plain(e.value)};
}

Object? _plain(Object? value) => switch (value) {
      YamlMap() => {for (final e in value.entries) '${e.key}': _plain(e.value)},
      YamlList() => [for (final v in value) _plain(v)],
      _ => value,
    };
