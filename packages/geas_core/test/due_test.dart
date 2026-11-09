import 'package:geas_core/geas_core.dart';
import 'package:test/test.dart';

void main() {
  group('LocalDate', () {
    test('parses and prints', () {
      expect(LocalDate.parse('2026-11-08'), const LocalDate(2026, 11, 8));
      expect('${const LocalDate(2026, 1, 2)}', '2026-01-02');
    });

    test('rejects dates that do not exist', () {
      expect(() => LocalDate.parse('2026-02-30'), throwsFormatException);
      expect(() => LocalDate.parse('2026-13-01'), throwsFormatException);
      expect(() => LocalDate.parse('11/08/2026'), throwsFormatException);
    });

    test('adds days across months and years', () {
      expect(const LocalDate(2026, 12, 30).addDays(3),
          const LocalDate(2027, 1, 2));
      expect(const LocalDate(2026, 3, 1).addDays(-1),
          const LocalDate(2026, 2, 28));
    });
  });

  group('Due', () {
    test('parses a date', () {
      final due = Due.parse('2026-11-12');
      expect(due, const Due.date(LocalDate(2026, 11, 12)));
      expect(due.hasTime, isFalse);
      expect(due.instant, isNull);
      expect(due.localDate, const LocalDate(2026, 11, 12));
    });

    test('parses a time with an offset', () {
      final due = Due.parse('2026-11-12T09:00-06:00');
      expect(due.hour, 9);
      expect(due.offset, const Duration(hours: -6));
      expect(due.instant, DateTime.utc(2026, 11, 12, 15));
    });

    test('parses Z and compact offsets', () {
      expect(Due.parse('2026-11-12T09:30Z').instant,
          DateTime.utc(2026, 11, 12, 9, 30));
      expect(Due.parse('2026-11-12T09:30+0530').offset,
          const Duration(hours: 5, minutes: 30));
    });

    test('a time without an offset floats in local time', () {
      final due = Due.parse('2026-11-12T09:00');
      expect(due.offset, isNull);
      expect(due.instant, DateTime(2026, 11, 12, 9));
      expect(due.localDate, const LocalDate(2026, 11, 12));
    });

    test('drops seconds', () {
      expect(Due.parse('2026-11-12T09:00:59-06:00'),
          Due.parse('2026-11-12T09:00-06:00'));
    });

    for (final text in [
      '2026-11-12',
      '2026-11-12T09:00',
      '2026-11-12T09:00Z',
      '2026-11-12T09:00-06:00',
      '2026-11-12T23:45+05:30',
    ]) {
      test('prints $text back unchanged', () {
        expect('${Due.parse(text)}', text);
      });
    }

    for (final text in ['tomorrow', '2026-11-12T24:00', '2026-11-12T09', '']) {
      test('rejects "$text"', () {
        expect(() => Due.parse(text), throwsFormatException);
      });
    }
  });

  group('Priority', () {
    test('parses any case', () {
      expect(Priority.parse('High'), Priority.high);
      expect(Priority.parse('none'), Priority.none);
    });

    test('rejects unknown values', () {
      expect(() => Priority.parse('urgent'), throwsFormatException);
    });

    test('orders by index', () {
      expect(Priority.high.index, greaterThan(Priority.medium.index));
      expect(Priority.low.index, greaterThan(Priority.none.index));
    });
  });
}
