import 'package:geas_core/geas_core.dart';

import 'command.dart';
import 'context.dart';
import 'output.dart';
import 'session.dart';

/// The tracker [input] names, by id or name, ignoring case, or by the start
/// of either if only one matches.
Tracker resolveTracker(Session session, String input) {
  final trackers = session.workspace.trackers;
  final lower = input.trim().toLowerCase();
  bool named(Tracker t, bool Function(String text) test) =>
      test(t.id.toLowerCase()) || test(t.name.toLowerCase());
  final exact = trackers.where((t) => named(t, (text) => text == lower));
  if (exact.isNotEmpty) return exact.first;
  final starts = lower.isEmpty
      ? const <Tracker>[]
      : trackers.where((t) => named(t, (text) => text.startsWith(lower)));
  if (starts.length == 1) return starts.single;
  if (trackers.isEmpty) {
    throw const CliException(
        'Nothing is tracked yet. Add something with `geas health add <name>`.');
  }
  throw CliException(
      '${starts.isEmpty ? 'Nothing tracked matches' : 'More than one matches'} '
      '"$input". Tracked: ${trackers.map((t) => t.id).join(', ')}.');
}

/// How often [tracker] has been logged, as one line.
String trackerSummary(Tracker tracker, DateTime now) {
  final stats = TrackerStats.of(tracker, now);
  final since = stats.sinceLast;
  if (since == null) return 'nothing logged';
  final gap = stats.averageGap;
  return [
    '${tracker.kind.done.toLowerCase()} ${spanLabel(since)} ago',
    if (tracker.kind == TrackerKind.sensor) ...[
      if (wearDay(tracker, now) case final day?) day,
      if (gap != null) 'lasts ${spanLabel(gap)} on average',
    ] else ...[
      '${stats.today} today',
      '${oneDecimal(stats.perDayWeek!)} a day this week',
    ],
  ].join(', ');
}

class HealthCommand extends GeasCommand {
  HealthCommand(super.context) {
    argParser
      ..addOption('kind',
          help: 'For add: med (the default), or sensor for something '
              'replaced every several days.')
      ..addOption('every',
          help: 'For add: how often it\'s meant to happen, like 12h or 10d.')
      ..addOption('number',
          abbr: 'n',
          help: 'For show: how many times to list.',
          defaultsTo: '20');
  }

  @override
  final name = 'health';

  @override
  final description = 'Show what\'s tracked (medications, CGM sensors) and '
      'how often each is logged, or add or remove one. Log a time with '
      '`geas log`.';

  @override
  String get invocation => 'geas health\n'
      '       geas health show <name> [-n <count>]\n'
      '       geas health add <name> [--kind med|sensor] [--every <interval>]\n'
      '       geas health rm <name>';

  @override
  Future<int> run() async {
    final session = await openSession();
    return switch (rest) {
      [] => _list(session),
      ['show', ...final words] when words.isNotEmpty =>
        _show(session, words.join(' ')),
      ['add', ...final words] when words.isNotEmpty =>
        _add(session, words.join(' ')),
      ['rm', ...final words] when words.isNotEmpty =>
        _remove(session, words.join(' ')),
      _ => usageException('Unknown or incomplete `geas health` command.'),
    };
  }

  Future<int> _list(Session session) async {
    await session.pull();
    final trackers = session.workspace.trackers;
    if (trackers.isEmpty) {
      out.writeln('Nothing is tracked yet. Add something with '
          '`geas health add <name>`.');
      return 0;
    }
    final now = context.clock();
    int width(String Function(Tracker t) text) =>
        trackers.fold(0, (w, t) => text(t).length > w ? text(t).length : w);
    final idWidth = width((t) => t.id), nameWidth = width((t) => t.name);
    for (final t in trackers) {
      out.writeln('  ${t.id.padRight(idWidth)}  ${t.name.padRight(nameWidth)}'
          '  ${trackerSummary(t, now)}');
    }
    return 0;
  }

  Future<int> _show(Session session, String input) async {
    final count = int.tryParse(argResults!['number'] as String);
    if (count == null || count < 1) usageException('-n takes a number.');
    await session.pull();
    final tracker = resolveTracker(session, input);
    final now = context.clock();
    final stats = TrackerStats.of(tracker, now);
    final every = tracker.every;
    out.writeln('${tracker.name} (${tracker.id}), '
        '${tracker.kind.label.toLowerCase()}'
        '${every == null ? '' : ', every ${spanLabel(every)}'}');
    if (stats.count == 0) {
      out.writeln('  Nothing logged. Log a time with '
          '`geas log ${tracker.id}`.');
      return 0;
    }
    String rate(int n, double? perDay) => '$n (${oneDecimal(perDay!)} a day)';
    out
      ..writeln('  ${tracker.kind.done} ${_times(stats.count)} since '
          '${formatDate(LocalDate.of(stats.first!.toLocal()))}; last '
          '${spanLabel(stats.sinceLast!)} ago.')
      ..writeln('  Today ${stats.today}, 7 days '
          '${rate(stats.week, stats.perDayWeek)}, 30 days '
          '${rate(stats.month, stats.perDayMonth)}.');
    final gap = stats.averageGap, due = stats.nextDue;
    if (gap != null) out.writeln('  ${spanLabel(gap)} apart on average.');
    if (due != null) {
      out.writeln('  Next due ${formatTime(due)}'
          '${due.isBefore(now) ? ' (overdue)' : ''}.');
    }
    out.writeln();
    for (final (:entry, :gap) in entryGaps(tracker).take(count)) {
      out.writeln([
        '  ${formatTime(entry.at)}',
        if (gap != null) 'after ${spanLabel(gap)}',
        if (entry.note != null) entry.note!,
      ].join('  '));
    }
    return 0;
  }

  Future<int> _add(Session session, String name) async {
    final kindText = argResults!['kind'] as String?;
    final everyText = argResults!['every'] as String?;
    final kind = TrackerKind.values
        .where((k) => k.yaml == (kindText ?? 'med').toLowerCase())
        .firstOrNull;
    if (kind == null) usageException('--kind is med or sensor.');
    await session.pull();
    final Tracker tracker;
    try {
      tracker = newTracker(
        name,
        session.workspace.trackers,
        kind: kind,
        every: everyText == null ? null : parseInterval(everyText),
      );
    } on FormatException catch (e) {
      throw CliException(e.message);
    }
    await session.workspace.saveTracker(tracker);
    out.writeln('Tracking ${tracker.name} (${tracker.id}). Log a time with '
        '`geas log ${tracker.id}`.');
    await session.push();
    return 0;
  }

  Future<int> _remove(Session session, String input) async {
    await session.pull();
    final tracker = resolveTracker(session, input);
    final count = tracker.entries.length;
    if (count > 0 &&
        !context.confirm('Remove ${tracker.name} and its ${_times(count)} '
            'logged?')) {
      throw const CliException('Nothing removed.');
    }
    await session.workspace.deleteTracker(tracker.id);
    out.writeln('Removed ${tracker.name}.');
    await session.push();
    return 0;
  }
}

class LogCommand extends GeasCommand {
  LogCommand(super.context) {
    argParser
      ..addOption('at',
          help: 'When, if not now: 8am, 08:15, "yesterday 9pm" or '
              '"2026-11-14 21:00".')
      ..addOption('note', help: 'A note to keep with this time.')
      ..addFlag('undo',
          negatable: false, help: 'Remove the latest time logged instead.');
  }

  @override
  final name = 'log';

  @override
  final aliases = const ['take'];

  @override
  final description = 'Log that you took a medication or replaced a sensor, '
      'now or at another time.';

  @override
  String get invocation =>
      'geas log <name> [--at <when>] [--note <text>] [--undo]';

  @override
  Future<int> run() async {
    if (rest.isEmpty) usageException('Say what to log; see `geas health`.');
    final args = argResults!;
    final session = await openSession();
    await session.pull();
    final tracker = resolveTracker(session, rest.join(' '));
    final now = context.clock();

    if (args['undo'] as bool) {
      final latest = tracker.entries.lastOrNull;
      if (latest == null) {
        throw CliException('${tracker.name} has nothing logged.');
      }
      await session.workspace.saveTracker(tracker.withoutEntry(latest));
      out.writeln('Removed ${tracker.name} at ${formatTime(latest.at)}.');
      await session.push();
      return 0;
    }

    final atText = args['at'] as String?;
    final DateTime at;
    try {
      at = atText == null ? now : parseLogTime(atText, now: now);
    } on FormatException catch (e) {
      throw CliException('--at: ${e.message}');
    }
    final saved = await session.workspace
        .saveTracker(tracker.log(at, note: args['note'] as String?));
    out.writeln('${tracker.kind.done} ${tracker.name} at ${formatTime(at)}; '
        '${trackerSummary(saved, now)}.');
    await session.push();
    return 0;
  }
}

String _times(int n) => n == 1 ? '1 time' : '$n times';
