import 'package:geas_core/geas_core.dart';
import 'package:test/test.dart';

void main() {
  const body = '''Some notes.

- [ ] first
* [X] second
  + [ ] nested
- not a checkbox
- [] not one either

```
- [ ] inside a code block
```
- [x] last''';

  test('finds checkboxes and their state', () {
    expect(parseChecklist(body), const [
      ChecklistItem(line: 2, text: 'first', done: false),
      ChecklistItem(line: 3, text: 'second', done: true),
      ChecklistItem(line: 4, text: 'nested', done: false, indent: 2),
      ChecklistItem(line: 11, text: 'last', done: true),
    ]);
  });

  test('an empty body has no checklist', () {
    expect(parseChecklist(''), isEmpty);
  });

  test('checks and unchecks one line, leaving the rest alone', () {
    final checked = setChecklistLine(body, 4, done: true);
    expect(checked.split('\n')[4], '  + [x] nested');
    expect(checked.replaceFirst('[x] nested', '[ ] nested'), body);

    final unchecked = setChecklistLine(body, 3, done: false);
    expect(unchecked.split('\n')[3], '* [ ] second');
  });

  test('keeps CRLF line endings', () {
    final crlf = body.replaceAll('\n', '\r\n');
    expect(parseChecklist(crlf).first.text, 'first');
    expect(setChecklistLine(crlf, 2, done: true), contains('- [x] first\r\n'));
  });

  test('refuses a line that is not a checklist item', () {
    expect(() => setChecklistLine(body, 5, done: true), throwsArgumentError);
    expect(() => setChecklistLine(body, 9, done: true), throwsArgumentError);
  });

  group('addChecklistItem', () {
    test('goes after the last item', () {
      expect(
        addChecklistItem('Notes.\n\n- [ ] a\n- [x] b\n\nMore.\n', ' c '),
        'Notes.\n\n- [ ] a\n- [x] b\n- [ ] c\n\nMore.\n',
      );
    });

    test('starts a checklist after the notes', () {
      expect(addChecklistItem('Notes.\n', 'a'), 'Notes.\n\n- [ ] a\n');
      expect(addChecklistItem('', 'a'), '- [ ] a\n');
    });
  });

  test('removeChecklistLine drops only that item', () {
    expect(removeChecklistLine('- [ ] a\n- [x] b\nNotes.\n', 1),
        '- [ ] a\nNotes.\n');
    expect(() => removeChecklistLine('Notes.\n', 0), throwsArgumentError);
  });
}
