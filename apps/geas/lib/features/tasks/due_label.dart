import 'package:geas_core/geas_core.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _fullWeekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', //
  'Sunday',
];

/// "Today", "Tomorrow", "Yesterday", a weekday within the coming week, or a
/// short date ("Nov 12", with the year when it isn't this year).
String dayLabel(LocalDate day, DateTime now, {bool short = false}) {
  final today = LocalDate.of(now);
  if (day == today) return 'Today';
  if (day == today.addDays(1)) return 'Tomorrow';
  if (day == today.addDays(-1)) return 'Yesterday';
  final weekday = DateTime.utc(day.year, day.month, day.day).weekday - 1;
  if (day.isAfter(today) && day.isBefore(today.addDays(7))) {
    return short ? _weekdays[weekday] : _fullWeekdays[weekday];
  }
  final date = '${_months[day.month - 1]} ${day.day}';
  return day.year == today.year ? date : '$date, ${day.year}';
}

/// The due date as shown on a task: the day, plus the local time if timed.
String dueLabel(Due due, DateTime now) {
  final day = dayLabel(due.localDate, now, short: true);
  final instant = due.instant;
  if (instant == null) return day;
  final local = instant.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$day $hh:$mm';
}
