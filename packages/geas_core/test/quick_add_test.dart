import 'package:geas_core/geas_core.dart';
import 'package:test/test.dart';

void main() {
  // A Wednesday.
  final now = DateTime(2026, 11, 18, 12);
  const today = LocalDate(2026, 11, 18);
  const lists = [
    TaskList(id: 'pedals', name: 'Pedals'),
    TaskList(id: 'home', name: 'Home Repairs'),
  ];
  QuickAdd read(String text) => parseQuickAdd(text, now: now, lists: lists);

  test('plain text is just a title', () {
    final q = read('  Reply to the  luthier ');
    expect(q.title, 'Reply to the luthier');
    expect(q.tags, isEmpty);
    expect(q.list, isNull);
    expect(q.priority, isNull);
    expect(q.due, isNull);
  });

  test('reads tags, a list, a priority and a date', () {
    final q = read('Order 1N914s #tayda ^pedals !high #Pedals fri 5pm');
    expect(q.title, 'Order 1N914s');
    expect(q.tags, ['tayda', 'Pedals']);
    expect(q.list, 'pedals');
    expect(q.priority, Priority.high);
    expect(q.due!.date, const LocalDate(2026, 11, 20));
    expect((q.due!.hour, q.due!.minute), (17, 0));
  });

  test('words can come in any order, around the title', () {
    final q = read('!low Call #errands the dentist ^inbox tomorrow');
    expect(q.title, 'Call the dentist');
    expect(q.tags, ['errands']);
    expect(q.list, inboxId);
    expect(q.priority, Priority.low);
    expect(q.due, Due.date(today.addDays(1)));
  });

  test('priorities', () {
    expect(read('x !h').priority, Priority.high);
    expect(read('x !!!').priority, Priority.high);
    expect(read('x !MED').priority, Priority.medium);
    expect(read('x !!').priority, Priority.medium);
    expect(read('x !').priority, Priority.low);
    expect(read('x !none').priority, Priority.none);
    expect(read('Wow !important').title, 'Wow !important');
  });

  test('lists by id or name, and unknown ones stay in the title', () {
    expect(read('Fix door ^Home-Repairs').list, 'home');
    expect(read('Fix door ^HOME').list, 'home');
    final q = read('Fix door ^garage');
    expect(q.list, isNull);
    expect(q.title, 'Fix door ^garage');
  });

  test('a date counts only at the end', () {
    expect(read('Call mom today').due, const Due.date(today));
    expect(read('Call mom 2026-12-01').due,
        const Due.date(LocalDate(2026, 12, 1)));
    expect(read('Stand-up 9am').due!.hour, 9);
    final q = read('Plan tomorrow with Sam');
    expect(q.due, isNull);
    expect(q.title, 'Plan tomorrow with Sam');
    // A date after tags still ends the title.
    expect(
        read('Call mom fri #family').due!.date, const LocalDate(2026, 11, 20));
  });

  test('odd words are left alone', () {
    expect(read('Use C# and ## headers #').title, 'Use C# and ## headers #');
    expect(read('Issue #12').tags, ['12']);
  });

  test('something is always left for the title', () {
    expect(read('tomorrow').title, 'tomorrow');
    expect(read('tomorrow').due, isNull);
    expect(read('#tag !high').title, '#tag !high');
    expect(read('#tag !high').tags, isEmpty);
    expect(read('').title, '');
  });
}
