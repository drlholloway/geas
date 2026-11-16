import 'local_date.dart';
import 'task.dart' show splitFrontmatter;
import 'yaml_fields.dart';

final _idPattern = RegExp(r'^[A-Za-z0-9_-]+$');
final _entryPattern = RegExp(
  r'^\s*[-*]\s+'
  r'(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(?::\d{2})?(?:Z|[+-]\d{2}:?\d{2})?)'
  r'(?:\s+(.*))?$',
);
final _intervalPattern = RegExp(r'^(\d+)\s*([hdw])$');
const _keep = Object();

/// What a tracker logs, which sets its wording and which numbers matter.
enum TrackerKind {
  /// Something taken, often several times a day: doses per day matter.
  med('med', 'Medication', 'Take', 'Taken'),

  /// Something replaced every several days, such as a CGM sensor: how long
  /// each one lasted matters.
  sensor('sensor', 'Sensor', 'Replace', 'Replaced');

  const TrackerKind(this.yaml, this.label, this.action, this.done);

  /// As written in the file.
  final String yaml;
  final String label;

  /// The verb on the button that logs it, and its past tense.
  final String action, done;

  /// Reads the file form. A kind this build doesn't know reads as [med];
  /// the file keeps what it says.
  static TrackerKind parse(String? text) =>
      values.where((k) => k.yaml == text?.trim().toLowerCase()).firstOrNull ??
      med;
}

/// One logged time in a tracker: a body line such as
/// `- 2026-11-15T08:02:11-06:00 with dinner`.
class TrackerEntry {
  const TrackerEntry(this.at, {this.note, this.line = -1});

  /// When, in UTC.
  final DateTime at;
  final String? note;

  /// The index of its line in the tracker's body.
  final int line;

  @override
  bool operator ==(Object other) =>
      other is TrackerEntry && other.at == at && other.note == note;

  @override
  int get hashCode => Object.hash(at, note);

  @override
  String toString() => 'TrackerEntry($at${note == null ? '' : ', $note'})';
}

/// Something logged each time it happens, such as taking a medication or
/// replacing a CGM sensor: a Markdown file `trackers/<id>.md` with YAML
/// frontmatter, then one list item per time.
class Tracker {
  Tracker({
    required this.id,
    required this.name,
    this.kind = TrackerKind.med,
    this.every,
    this.order = 0,
    this.body = '',
    this.frontmatter,
  });

  /// Parses a tracker file, throwing [FormatException] if it isn't valid.
  factory Tracker.parse(String text) {
    final parts = splitFrontmatter(text);
    if (parts == null) {
      throw const FormatException(
        'A tracker file starts with YAML frontmatter between "---" lines.',
      );
    }
    const what = 'The tracker';
    final map = parseYamlMap(
        parts.frontmatter.isEmpty ? '{}' : parts.frontmatter, 'Frontmatter');
    final id = requireString(map, 'id', what);
    if (!_idPattern.hasMatch(id)) {
      throw FormatException(
          'Tracker id "$id" may only use A-Z, a-z, 0-9, _ and -.');
    }
    final order = map['order'];
    if (order != null && order is! int) {
      throw const FormatException(
          '"order" in a tracker must be a whole number.');
    }
    final every = optionalString(map, 'every', what);
    return Tracker(
      id: id,
      name: requireString(map, 'name', what),
      kind: TrackerKind.parse(optionalString(map, 'kind', what)),
      every: every == null ? null : parseInterval(every),
      order: order as int? ?? 0,
      body: parts.body,
      frontmatter: parts.frontmatter,
    );
  }

  /// A slug, which is also the filename.
  final String id;
  final String name;
  final TrackerKind kind;

  /// How often it's meant to happen (`every: 10d` or `12h`), or null. The
  /// next one is due this long after the last.
  final Duration? every;

  /// Trackers sort by [order], then name.
  final int order;

  /// The log: one list item per time. Other lines are kept as notes.
  final String body;

  /// The frontmatter as it was read, or null if it hasn't been written.
  /// [encode] edits it in place, keeping comments and unknown keys.
  final String? frontmatter;

  /// Every logged time, oldest first.
  late final List<TrackerEntry> entries = _parseEntries(body);

  /// With [at] logged, to the second, in its place among the others.
  Tracker log(DateTime at, {String? note}) {
    final lines = _lines(body)..add(entryLine(at, note: note));
    return _withBody(_join(sortEntryLines(lines)));
  }

  /// Without [entry], if it's there.
  Tracker withoutEntry(TrackerEntry entry) {
    final found = entries.where((e) => e == entry);
    if (found.isEmpty) return this;
    final match =
        found.where((e) => e.line == entry.line).firstOrNull ?? found.first;
    return _withBody(_join(_lines(body)..removeAt(match.line)));
  }

  /// This tracker as a file. A parsed one changes only the fields that
  /// differ from what was read.
  String encode() {
    final source = frontmatter;
    final yaml = source == null || source.trim().isEmpty
        ? emitYamlMap({
            for (final MapEntry(:key, :value) in _fields().entries)
              if (value != null) key: value,
          })
        : patchYamlMap(
            source, _fields(), Tracker.parse('---\n$source---\n')._fields());
    return '---\n$yaml---\n$body';
  }

  Map<String, Object?> _fields() => {
        'id': id,
        'name': name,
        'kind': kind.yaml,
        'every': every == null ? null : formatInterval(every!),
        'order': order,
      };

  Tracker _withBody(String body) => Tracker(
        id: id,
        name: name,
        kind: kind,
        every: every,
        order: order,
        body: body,
        frontmatter: frontmatter,
      );

  /// A copy with the given fields replaced. Pass null for [every] to clear
  /// it.
  Tracker copyWith({
    String? name,
    TrackerKind? kind,
    Object? every = _keep,
    int? order,
  }) =>
      Tracker(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        every: identical(every, _keep) ? this.every : every as Duration?,
        order: order ?? this.order,
        body: body,
        frontmatter: frontmatter,
      );

  /// Equal fields and log; [frontmatter] isn't compared.
  @override
  bool operator ==(Object other) =>
      other is Tracker &&
      other.id == id &&
      other.name == name &&
      other.kind == kind &&
      other.every == every &&
      other.order == order &&
      other.body == body;

  @override
  int get hashCode => Object.hash(id, name, kind, every, order, body);

  @override
  String toString() => 'Tracker($id, $name)';
}

/// Where the tracker with [id] is stored.
String trackerPath(String id) => 'trackers/$id.md';

/// Whether [path] is where a tracker file goes.
bool isTrackerPath(String path) =>
    path.startsWith('trackers/') && path.endsWith('.md');

/// [trackers] in display order.
List<Tracker> sortTrackers(Iterable<Tracker> trackers) => trackers.toList()
  ..sort((a, b) {
    final byOrder = a.order.compareTo(b.order);
    return byOrder != 0
        ? byOrder
        : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

/// [trackers] with [id] moved to [index] (0 is first): the ones whose
/// `order` has to change for that, renumbered from 1. Empty if nothing
/// moves.
List<Tracker> moveTracker(Iterable<Tracker> trackers, String id, int index) {
  final sorted = sortTrackers(trackers);
  final from = sorted.indexWhere((t) => t.id == id);
  if (from < 0) return const [];
  final moved = sorted.removeAt(from);
  sorted.insert(index.clamp(0, sorted.length), moved);
  return [
    for (final (i, t) in sorted.indexed)
      if (t.order != i + 1) t.copyWith(order: i + 1),
  ];
}

/// A new tracker called [name], ordered after [trackers], with an id made
/// from the name that none of them has. Throws [FormatException] if the
/// name has no letter or digit, or a tracker already has it.
Tracker newTracker(
  String name,
  Iterable<Tracker> trackers, {
  TrackerKind kind = TrackerKind.med,
  Duration? every,
}) {
  name = name.trim();
  if (trackers.any((t) => t.name.toLowerCase() == name.toLowerCase())) {
    throw FormatException('"$name" is already tracked.');
  }
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.isEmpty) {
    throw const FormatException('A name needs a letter or digit.');
  }
  var id = slug;
  for (var n = 2; trackers.any((t) => t.id == id); n++) {
    id = '$slug-$n';
  }
  final order = trackers.fold(0, (o, t) => t.order > o ? t.order : o) + 1;
  return Tracker(id: id, name: name, kind: kind, every: every, order: order);
}

/// Parses an interval such as `12h`, `10d` or `2w`, throwing
/// [FormatException] for anything else.
Duration parseInterval(String text) {
  final m = _intervalPattern.firstMatch(text.trim().toLowerCase());
  final count = m == null ? 0 : int.parse(m[1]!);
  if (m == null || count == 0) {
    throw FormatException(
        'Expected an interval like 12h, 10d or 2w, got "$text".');
  }
  return switch (m[2]) {
    'h' => Duration(hours: count),
    'd' => Duration(days: count),
    _ => Duration(days: 7 * count),
  };
}

/// [interval] as [parseInterval] reads it: whole days as `10d`, anything
/// else in hours.
String formatInterval(Duration interval) =>
    interval.inHours % 24 == 0 ? '${interval.inDays}d' : '${interval.inHours}h';

/// The body line for an entry at [at]: local time with its offset, to the
/// second, then the note.
String entryLine(DateTime at, {String? note}) {
  final t = at.toLocal();
  final offset = t.timeZoneOffset;
  final minutes = offset.inMinutes.abs();
  final zone = '${offset.isNegative ? '-' : '+'}'
      '${_two(minutes ~/ 60)}:${_two(minutes % 60)}';
  final text = note?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
  return '- ${LocalDate.of(t)}T${_two(t.hour)}:${_two(t.minute)}:'
      '${_two(t.second)}$zone${text.isEmpty ? '' : ' $text'}';
}

/// [lines] with the entry lines in time order. Other lines stay where they
/// are.
List<String> sortEntryLines(List<String> lines) {
  final slots = <int>[];
  final found = <(DateTime, String)>[];
  for (var i = 0; i < lines.length; i++) {
    final at = _entryTime(lines[i]);
    if (at == null) continue;
    slots.add(i);
    found.add((at, lines[i]));
  }
  found.sort((a, b) {
    final byTime = a.$1.compareTo(b.$1);
    return byTime != 0 ? byTime : a.$2.compareTo(b.$2);
  });
  final sorted = [...lines];
  for (var k = 0; k < slots.length; k++) {
    sorted[slots[k]] = found[k].$2;
  }
  return sorted;
}

/// Three-way merge of tracker logs as sets of lines, so two devices that
/// each log a time never conflict: the [remote] log, without the lines
/// [local] removed since [base], plus the ones it added, in time order.
String mergeTrackerBodies(String base, String local, String remote) {
  final b = _lines(base).toSet();
  final l = _lines(local), r = _lines(remote);
  final inLocal = l.toSet(), inRemote = r.toSet();
  return _join(sortEntryLines([
    for (final line in r)
      if (!b.contains(line) || inLocal.contains(line)) line,
    for (final line in l)
      if (!b.contains(line) && !inRemote.contains(line)) line,
  ]));
}

List<TrackerEntry> _parseEntries(String body) {
  final lines = _lines(body);
  final entries = <TrackerEntry>[];
  for (var i = 0; i < lines.length; i++) {
    final m = _entryPattern.firstMatch(lines[i]);
    final at = m == null ? null : DateTime.tryParse(m[1]!);
    if (at == null) continue;
    final note = m![2]?.trim() ?? '';
    entries.add(
        TrackerEntry(at.toUtc(), note: note.isEmpty ? null : note, line: i));
  }
  // Stable, so entries at the same moment keep their file order.
  final indexed = entries.indexed.toList()
    ..sort((a, b) {
      final byTime = a.$2.at.compareTo(b.$2.at);
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });
  return List.unmodifiable([for (final (_, e) in indexed) e]);
}

DateTime? _entryTime(String line) {
  final m = _entryPattern.firstMatch(line);
  return m == null ? null : DateTime.tryParse(m[1]!)?.toUtc();
}

/// The lines of [body], without the empty one after a final newline.
List<String> _lines(String body) {
  if (body.isEmpty) return [];
  final lines = body.split('\n');
  if (lines.last.isEmpty) lines.removeLast();
  return lines;
}

String _join(List<String> lines) =>
    lines.isEmpty ? '' : '${lines.join('\n')}\n';

String _two(int n) => n.toString().padLeft(2, '0');
