import 'due.dart';
import 'due_input.dart';
import 'priority.dart';
import 'task_list.dart';

/// What [parseQuickAdd] read out of a line of text.
class QuickAdd {
  const QuickAdd({
    required this.title,
    this.tags = const [],
    this.list,
    this.priority,
    this.due,
  });

  /// The text with everything that was understood taken out.
  final String title;

  /// From `#tag` words.
  final List<String> tags;

  /// The id of the list a `^list` word names, or null.
  final String? list;

  /// From `!high`, `!med`, `!low`, or `!!!`, `!!`, `!`; null if not given.
  final Priority? priority;

  /// From a date at the end, like `tomorrow` or `fri 5pm`; null if none.
  final Due? due;
}

const _priorities = {
  'high': Priority.high,
  'h': Priority.high,
  '!!': Priority.high,
  'medium': Priority.medium,
  'med': Priority.medium,
  'm': Priority.medium,
  '!': Priority.medium,
  'low': Priority.low,
  'l': Priority.low,
  '': Priority.low,
  'none': Priority.none,
  'n': Priority.none,
};

/// Reads a task typed on one line, relative to [now]:
///
/// - `#tag` adds a tag.
/// - `^list` puts it in one of [lists], named by id or by name (with `-`
///   for spaces), ignoring case.
/// - `!high`, `!med` or `!low` (or `!!!`, `!!`, `!`) sets the priority.
/// - A date at the very end sets when it's due: `today`, `tomorrow`, a
///   weekday or `YYYY-MM-DD`, optionally with a time (`fri 5pm`), or a
///   time alone for today.
///
/// Anything that doesn't fit one of those, such as `^nosuchlist` or a `#`
/// on its own, stays in the title. So does everything if nothing else
/// would be left for a title.
QuickAdd parseQuickAdd(
  String text, {
  required DateTime now,
  Iterable<TaskList> lists = const [],
}) {
  final words = text.trim().split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  final kept = <String>[];
  final tags = <String>[];
  String? list;
  Priority? priority;

  for (final word in words) {
    if (word.startsWith('#') && word.length > 1 && !word.startsWith('##')) {
      final tag = word.substring(1);
      if (!tags.any((t) => t.toLowerCase() == tag.toLowerCase())) tags.add(tag);
    } else if (_listNamed(word.substring(1), lists) case final id?
        when word.startsWith('^')) {
      list = id;
    } else if (_priorities[word.substring(1).toLowerCase()] case final p?
        when word.startsWith('!')) {
      priority = p;
    } else {
      kept.add(word);
    }
  }

  // The longest date that ends the line and still leaves a title.
  Due? due;
  for (final take in [2, 1]) {
    if (kept.length <= take) continue;
    try {
      due = parseDueInput(kept.sublist(kept.length - take).join(' '), now: now);
      kept.removeRange(kept.length - take, kept.length);
      break;
    } on FormatException {
      // Not a date; part of the title.
    }
  }

  if (kept.isEmpty) return QuickAdd(title: text.trim());
  return QuickAdd(
    title: kept.join(' '),
    tags: tags,
    list: list,
    priority: priority,
    due: due,
  );
}

String? _listNamed(String name, Iterable<TaskList> lists) {
  final wanted = name.toLowerCase();
  if (wanted.isEmpty) return null;
  for (final list in withInbox(lists)) {
    if (list.id.toLowerCase() == wanted ||
        list.name.toLowerCase().replaceAll(RegExp(r'\s+'), '-') == wanted) {
      return list.id;
    }
  }
  return null;
}
