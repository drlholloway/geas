import 'package:geas_cli/src/output.dart';
import 'package:geas_core/geas_core.dart';
import 'package:test/test.dart';

void main() {
  // Monday, November 9, 2026.
  final now = DateTime(2026, 11, 9, 12);
  String label(LocalDate date) => dueLabel(Due.date(date), now);

  test('due labels are relative within the week', () {
    expect(label(const LocalDate(2026, 11, 8)), 'yesterday');
    expect(label(const LocalDate(2026, 11, 9)), 'today');
    expect(label(const LocalDate(2026, 11, 10)), 'tomorrow');
    expect(label(const LocalDate(2026, 11, 11)), 'Wed');
    expect(label(const LocalDate(2026, 11, 15)), 'Sun');
    expect(label(const LocalDate(2026, 11, 16)), '2026-11-16');
    expect(label(const LocalDate(2026, 11, 1)), '2026-11-01');
  });

  test('a timed due shows the time here', () {
    expect(dueLabel(Due.at(const LocalDate(2026, 11, 9), 17, 5), now),
        'today 17:05');
  });

  test('task rows line up and drop empty columns', () {
    final created = DateTime.utc(2026, 11, 1);
    Task task(String id, String title, {Due? due, Priority? priority}) => Task(
        id: id,
        title: title,
        created: created,
        updated: created,
        due: due,
        priority: priority ?? Priority.none,
        tags: id == 'B' ? ['x'] : const [],
        list: id == 'B' ? 'work' : inboxId);

    expect(
      taskRows([task('A', 'One'), task('B', 'Two')],
          now: now, shortId: (id) => id),
      ['  A  One', '  B  Two  #x  @work'],
    );
    expect(
      taskRows([
        task('A', 'One', due: Due.date(const LocalDate(2026, 11, 9))),
        task('BB', 'Two', priority: Priority.high),
      ], now: now, shortId: (id) => id, showList: false),
      ['  A   today       One', '  BB         !!!  Two'],
    );
  });
}
