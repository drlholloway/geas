/// A calendar date with no time of day or time zone.
class LocalDate implements Comparable<LocalDate> {
  const LocalDate(this.year, this.month, this.day);

  /// The date of [dateTime] in its own time zone.
  factory LocalDate.of(DateTime dateTime) =>
      LocalDate(dateTime.year, dateTime.month, dateTime.day);

  /// Parses `YYYY-MM-DD`, throwing [FormatException] for anything else,
  /// including dates that don't exist.
  factory LocalDate.parse(String text) {
    final m = _pattern.firstMatch(text);
    if (m == null) throw FormatException('Expected YYYY-MM-DD, got "$text".');
    final date = LocalDate(
      int.parse(m[1]!),
      int.parse(m[2]!),
      int.parse(m[3]!),
    );
    final check = DateTime.utc(date.year, date.month, date.day);
    if (check.month != date.month || check.day != date.day) {
      throw FormatException('No such date: "$text".');
    }
    return date;
  }

  static final _pattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  final int year;
  final int month;
  final int day;

  LocalDate addDays(int days) =>
      LocalDate.of(DateTime.utc(year, month, day + days));

  bool isBefore(LocalDate other) => compareTo(other) < 0;
  bool isAfter(LocalDate other) => compareTo(other) > 0;

  @override
  int compareTo(LocalDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}
