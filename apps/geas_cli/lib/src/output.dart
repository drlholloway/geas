import 'package:geas_core/geas_core.dart';

const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// When [due] is, relative to [now]: `today`, `tomorrow`, `yesterday`, a
/// weekday within the next week, or the date; then the time, if any.
String dueLabel(Due due, DateTime now) {
  final today = LocalDate.of(now.toLocal());
  final date = due.localDate;
  final days = _daysBetween(today, date);
  final day = switch (days) {
    0 => 'today',
    1 => 'tomorrow',
    -1 => 'yesterday',
    > 1 && < 7 => _weekdayNames[_weekday(date) - 1],
    _ => '$date',
  };
  return due.hasTime ? '$day ${dueTime(due)}' : day;
}

/// The time of day [due] falls at here, as `HH:MM`, or '' for a date.
String dueTime(Due due) {
  final instant = due.instant?.toLocal();
  if (instant == null) return '';
  return '${_two(instant.hour)}:${_two(instant.minute)}';
}

/// `!`, `!!` or `!!!` for low, medium and high.
String priorityMarks(Priority priority) => '!' * priority.index;

/// A timestamp in local time, to the minute.
String formatTime(DateTime time) {
  final t = time.toLocal();
  return '${LocalDate.of(t)} ${_two(t.hour)}:${_two(t.minute)}';
}

/// `Mon 2026-11-09`.
String formatDate(LocalDate date) =>
    '${_weekdayNames[_weekday(date) - 1]} $date';

/// One row per task: short id, due, priority, title, tags and, unless
/// [showList] is false, the list. Columns with nothing in them are left out.
List<String> taskRows(
  List<Task> tasks, {
  required DateTime now,
  required String Function(String id) shortId,
  bool showList = true,
  String Function(Task task)? when,
}) {
  final whenOf = when ?? (Task t) => t.due == null ? '' : dueLabel(t.due!, now);
  final ids = [for (final t in tasks) shortId(t.id)];
  final whens = [for (final t in tasks) whenOf(t)];
  final marks = [for (final t in tasks) priorityMarks(t.priority)];
  int width(List<String> column) =>
      column.fold(0, (w, s) => s.length > w ? s.length : w);
  final idWidth = width(ids),
      whenWidth = width(whens),
      markWidth = width(marks);

  return [
    for (var i = 0; i < tasks.length; i++)
      [
        '  ${ids[i].padRight(idWidth)}',
        if (whenWidth > 0) whens[i].padRight(whenWidth),
        if (markWidth > 0) marks[i].padRight(markWidth),
        [
          tasks[i].title,
          for (final tag in tasks[i].tags) '#$tag',
          if (showList && tasks[i].list != inboxId) '@${tasks[i].list}',
        ].join('  '),
      ].join('  ').trimRight(),
  ];
}

int _daysBetween(LocalDate a, LocalDate b) =>
    DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;

int _weekday(LocalDate date) =>
    DateTime.utc(date.year, date.month, date.day).weekday;

String _two(int n) => n.toString().padLeft(2, '0');
