import 'package:geas_core/geas_core.dart';
import 'package:test/test.dart';

void main() {
  // Monday, November 9, 2026, at noon on this machine.
  final now = DateTime(2026, 11, 9, 12);
  Due parse(String text) => parseDueInput(text, now: now);

  test('today and tomorrow', () {
    expect(parse('today'), const Due.date(LocalDate(2026, 11, 9)));
    expect(parse('Tomorrow'), const Due.date(LocalDate(2026, 11, 10)));
    expect(parse('tom'), const Due.date(LocalDate(2026, 11, 10)));
  });

  test('a weekday is the next one after today', () {
    expect(parse('wed'), const Due.date(LocalDate(2026, 11, 11)));
    expect(parse('Friday'), const Due.date(LocalDate(2026, 11, 13)));
    expect(parse('sun'), const Due.date(LocalDate(2026, 11, 15)));
    expect(parse('mon'), const Due.date(LocalDate(2026, 11, 16)));
  });

  test('a date', () {
    expect(parse('2026-12-01'), const Due.date(LocalDate(2026, 12, 1)));
    expect(() => parse('2026-02-30'), throwsFormatException);
  });

  test('a day and a time, with the local offset', () {
    final due = parse('fri 17:00');
    expect(due.date, const LocalDate(2026, 11, 13));
    expect((due.hour, due.minute), (17, 0));
    expect(due.instant!.isAtSameMomentAs(DateTime(2026, 11, 13, 17)), isTrue);
    expect(due.offset, DateTime(2026, 11, 13, 17).timeZoneOffset);
  });

  test('12-hour times', () {
    Due at(String text) => parse('tomorrow $text');
    expect((at('5pm').hour, at('5pm').minute), (17, 0));
    expect((at('5:30am').hour, at('5:30am').minute), (5, 30));
    expect(at('12am').hour, 0);
    expect(at('12pm').hour, 12);
  });

  test('a time alone means today', () {
    final due = parse('9:15');
    expect(due.date, const LocalDate(2026, 11, 9));
    expect((due.hour, due.minute), (9, 15));
  });

  test('rejects anything else', () {
    for (final text in [
      '',
      'someday',
      'fri fri',
      'fri 25:00',
      '13pm',
      'today 5pm extra',
    ]) {
      expect(() => parse(text), throwsFormatException, reason: text);
    }
  });
}
