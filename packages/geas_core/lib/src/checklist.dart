final _itemPattern = RegExp(r'^(\s*)[-*+] \[([ xX])\] (.*?)\r?$');
final _fencePattern = RegExp(r'^\s*(```|~~~)');

/// A Markdown checkbox (`- [ ] text`) in a task body.
class ChecklistItem {
  const ChecklistItem({
    required this.line,
    required this.text,
    required this.done,
    this.indent = 0,
  });

  /// Zero-based line in the body; pass it to [setChecklistLine].
  final int line;
  final String text;
  final bool done;

  /// Leading whitespace, in characters; nested items are indented.
  final int indent;

  @override
  bool operator ==(Object other) =>
      other is ChecklistItem &&
      other.line == line &&
      other.text == text &&
      other.done == done &&
      other.indent == indent;

  @override
  int get hashCode => Object.hash(line, text, done, indent);

  @override
  String toString() => 'ChecklistItem($line, ${done ? 'x' : ' '}, $text)';
}

/// The checkboxes in [body], skipping fenced code blocks.
List<ChecklistItem> parseChecklist(String body) {
  final items = <ChecklistItem>[];
  var inFence = false;
  final lines = body.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (_fencePattern.hasMatch(lines[i])) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    final m = _itemPattern.firstMatch(lines[i]);
    if (m == null) continue;
    items.add(ChecklistItem(
      line: i,
      text: m[3]!,
      done: m[2] != ' ',
      indent: m[1]!.length,
    ));
  }
  return items;
}

/// [body] with the checkbox on [line] checked or unchecked. Throws
/// [ArgumentError] if that line isn't a checklist item.
String setChecklistLine(String body, int line, {required bool done}) {
  if (!parseChecklist(body).any((item) => item.line == line)) {
    throw ArgumentError.value(line, 'line', 'not a checklist item');
  }
  final lines = body.split('\n');
  final m = _itemPattern.firstMatch(lines[line])!;
  final mark = m[1]!.length + 3; // past the indent, the bullet, " ["
  lines[line] = lines[line].replaceRange(mark, mark + 1, done ? 'x' : ' ');
  return lines.join('\n');
}

/// [body] with an unchecked item for [text]: after the last checklist item,
/// or at the end after a blank line if there are none.
String addChecklistItem(String body, String text) {
  final item = '- [ ] ${text.trim()}';
  final items = parseChecklist(body);
  if (items.isEmpty) {
    final notes = body.trimRight();
    return notes.isEmpty ? '$item\n' : '$notes\n\n$item\n';
  }
  final lines = body.split('\n')..insert(items.last.line + 1, item);
  return lines.join('\n');
}

/// [body] without the checklist item on [line]. Throws [ArgumentError] if
/// that line isn't a checklist item.
String removeChecklistLine(String body, int line) {
  if (!parseChecklist(body).any((item) => item.line == line)) {
    throw ArgumentError.value(line, 'line', 'not a checklist item');
  }
  return (body.split('\n')..removeAt(line)).join('\n');
}
