import 'dart:convert';

import 'package:geas_core/geas_core.dart';
import 'package:geas_core/testing.dart';
import 'package:test/test.dart';

/// A local time on November [day], 2026.
DateTime _at(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 11, day, hour, minute);

Tracker _logged(Tracker tracker, Iterable<DateTime> times) =>
    times.fold(tracker, (t, at) => t.log(at));

void main() {
  final met = newTracker('Metformin', const []);

  group('file format', () {
    test('a new tracker is written in the canonical layout', () {
      final sensor = newTracker('CGM sensor', [met],
          kind: TrackerKind.sensor, every: const Duration(days: 10));
      expect(sensor.id, 'cgm-sensor');
      expect(
        sensor.encode(),
        '---\nid: cgm-sensor\nname: CGM sensor\nkind: sensor\nevery: 10d\n'
        'order: 2\n---\n',
      );
      expect(met.encode(), isNot(contains('every')));
      expect(Tracker.parse(sensor.encode()), sensor);
    });

    test('names must be new and usable as an id', () {
      expect(() => newTracker('metformin', [met]), throwsFormatException);
      expect(() => newTracker('!!', const []), throwsFormatException);
      expect(newTracker('Metformin XR', [met]).id, 'metformin-xr');
    });

    test('entries are read in time order, with notes and other lines kept', () {
      final tracker = Tracker.parse('---\nid: met\nname: Metformin\n---\n'
          'Started in October.\n'
          '- 2026-11-14T20:15:00Z with dinner\n'
          '- 2026-11-14 08:02\n'
          '* 2026-11-13T08:00-06:00\n'
          '- not a time\n');
      expect(tracker.kind, TrackerKind.med);
      expect(tracker.entries.map((e) => e.at), [
        DateTime.utc(2026, 11, 13, 14),
        _at(14, 8, 2).toUtc(),
        DateTime.utc(2026, 11, 14, 20, 15),
      ]);
      expect(tracker.entries.last.note, 'with dinner');
      expect(tracker.entries.first.note, isNull);
    });

    test('logging adds a line in its place', () {
      var tracker = met.log(_at(14, 20), note: 'with  dinner');
      tracker = tracker.log(_at(14, 8));
      tracker = Tracker.parse(tracker.encode());
      expect(tracker.entries.map((e) => e.at.toLocal()),
          [_at(14, 8), _at(14, 20)]);
      expect(tracker.entries.last.note, 'with dinner');
      expect(tracker.body, endsWith(' with dinner\n'));
      expect(tracker.body.split('\n').first,
          matches(RegExp(r'^- 2026-11-14T08:00:00[+-]\d\d:\d\d$')));
    });

    test('removing an entry takes out only its line', () {
      final tracker = _logged(met, [_at(13, 8), _at(14, 8), _at(15, 8)]);
      final without = tracker.withoutEntry(tracker.entries[1]);
      expect(
          without.entries.map((e) => e.at.toLocal()), [_at(13, 8), _at(15, 8)]);
      expect(without.withoutEntry(tracker.entries[1]), without);
    });

    test('a rewrite keeps comments, unknown keys and an unknown kind', () {
      const text = '---\n# my meds\nid: met\nname: Metformin\n'
          'kind: supplement\ndose: 500mg\n---\n';
      final tracker = Tracker.parse(text);
      expect(tracker.kind, TrackerKind.med);
      expect(tracker.encode(), text);
      expect(
        tracker.copyWith(name: 'Metformin XR').log(_at(14, 8)).encode(),
        allOf(contains('# my meds\n'), contains('kind: supplement\n'),
            contains('dose: 500mg\n'), contains('name: Metformin XR\n')),
      );
    });

    test('bad files are refused', () {
      expect(() => Tracker.parse('id: met\n'), throwsFormatException);
      expect(() => Tracker.parse('---\nid: met\n---\n'), throwsFormatException);
      expect(() => Tracker.parse('---\nid: met\nname: M\nevery: often\n---\n'),
          throwsFormatException);
    });

    test('intervals', () {
      expect(parseInterval('12h'), const Duration(hours: 12));
      expect(parseInterval('10 d'), const Duration(days: 10));
      expect(parseInterval('2w'), const Duration(days: 14));
      expect(formatInterval(const Duration(days: 14)), '14d');
      expect(formatInterval(const Duration(hours: 36)), '36h');
      expect(() => parseInterval('0d'), throwsFormatException);
      expect(() => parseInterval('10'), throwsFormatException);
    });
  });

  test('moving a tracker renumbers only what has to change', () {
    final a = newTracker('A', const []);
    final b = newTracker('B', [a]);
    final c = newTracker('C', [a, b]);
    List<String> after(List<Tracker> changed) => sortTrackers([
          for (final t in [a, b, c])
            changed.where((x) => x.id == t.id).firstOrNull ?? t,
        ]).map((t) => t.name).toList();

    final up = moveTracker([a, b, c], 'c', 0);
    expect(after(up), ['C', 'A', 'B']);
    expect(up, hasLength(3));
    final down = moveTracker([a, b, c], 'b', 99);
    expect(after(down), ['A', 'C', 'B']);
    expect(down.map((t) => t.id), ['c', 'b']);
    expect(moveTracker([a, b, c], 'b', 1), isEmpty);
    expect(moveTracker([a, b, c], 'nope', 0), isEmpty);
  });

  group('dose amounts', () {
    final insulin = newTracker('Insulin', const [], unit: 'u', dose: 12);

    test('the unit and usual dose are written and read back', () {
      expect(insulin.encode(),
          '---\nid: insulin\nname: Insulin\nkind: med\nunit: u\ndose: 12\norder: 1\n---\n');
      expect(Tracker.parse(insulin.encode()), insulin);
      final half = insulin.copyWith(dose: 2.5);
      expect(half.encode(), contains('dose: 2.5\n'));
      expect(Tracker.parse(half.encode()).dose, 2.5);
      expect(
          Tracker.parse(insulin.copyWith(unit: null, dose: null).encode()).unit,
          isNull);
    });

    test('an entry carries the usual dose, or the one given', () {
      var tracker = insulin.log(_at(14, 8));
      tracker = tracker.log(_at(14, 20), amount: 7.5, note: 'small dinner');
      tracker = Tracker.parse(tracker.encode());
      expect(tracker.body, contains(' 12u\n'));
      expect(tracker.body, endsWith(' 7.5u small dinner\n'));
      expect(tracker.entries.map((e) => e.amount), [12, 7.5]);
      expect(tracker.entries.last.note, 'small dinner');
      expect(tracker.withoutEntry(tracker.entries.first).entries.single.amount,
          7.5);
    });

    test('amounts are read only in the tracker\'s unit', () {
      final tracker =
          Tracker.parse('---\nid: met\nname: Metformin\nunit: mg\n---\n'
              '- 2026-11-14T08:00:00Z 500mg\n'
              '- 2026-11-14T12:00:00Z 250MG half\n'
              '- 2026-11-14T20:00:00Z 2 hours late\n'
              '- 2026-11-14T21:00:00Z 500mcg typo\n');
      expect(tracker.entries.map((e) => e.amount), [500, 250, null, null]);
      expect(tracker.entries.map((e) => e.note),
          [null, 'half', '2 hours late', '500mcg typo']);
      // With no unit, it's all note.
      final plain = Tracker.parse(
          '---\nid: met\nname: M\n---\n- 2026-11-14T08:00:00Z 500mg\n');
      expect(plain.entries.single.amount, isNull);
      expect(plain.entries.single.note, '500mg');
      expect(plain.log(_at(15, 8), amount: 5).entries.last.amount, isNull);
    });

    test('totals for today and per day', () {
      final now = _at(15, 12);
      var tracker = insulin;
      for (var day = 12; day <= 14; day++) {
        tracker = tracker.log(_at(day, 8)).log(_at(day, 20), amount: 8);
      }
      tracker = tracker.log(_at(15, 8), amount: 10);
      final stats = TrackerStats.of(tracker, now);
      expect(stats.amountToday, 10);
      expect(stats.amountPerDayWeek, closeTo(70 / 4, 1e-9));
      expect(dailyAmounts(tracker, now, days: 5), [0, 20, 20, 20, 10]);
      expect(TrackerStats.of(newTracker('Plain', const []), now).amountToday,
          isNull);
    });

    test('bad units and doses are refused', () {
      expect(() => Tracker.parse('---\nid: a\nname: A\nunit: fl oz\n---\n'),
          throwsFormatException);
      expect(() => Tracker.parse('---\nid: a\nname: A\ndose: lots\n---\n'),
          throwsFormatException);
      // The unit can ride on the dose, as people write it.
      final written = Tracker.parse('---\nid: a\nname: A\ndose: 500 mg\n---\n');
      expect((written.dose, written.unit), (500, 'mg'));
      expect(formatAmount(500), '500');
      expect(formatAmount(2.50), '2.5');
      expect(formatAmount(0.125), '0.125');
    });
  });

  group('stats', () {
    final now = _at(15, 12);

    test('nothing logged', () {
      final stats = TrackerStats.of(met, now);
      expect(stats.count, 0);
      expect(stats.last, isNull);
      expect(stats.perDayWeek, isNull);
      expect(stats.averageGap, isNull);
      expect(dailyCounts(met, now, days: 3), [0, 0, 0]);
    });

    test('a medication counts doses per day', () {
      // Twice a day from the 1st, once so far today, none on the 10th.
      final tracker = _logged(met, [
        for (var day = 1; day < 15; day++)
          if (day != 10) ...[_at(day, 8), _at(day, 20)],
        _at(15, 8),
      ]);
      final stats = TrackerStats.of(tracker, now);
      expect(stats.count, 27);
      expect(stats.today, 1);
      expect(stats.week, 11);
      expect(stats.month, 27);
      expect(stats.perDayWeek, closeTo(11 / 7, 1e-9));
      // Tracked for 15 days, so not averaged over 30.
      expect(stats.perDayMonth, closeTo(27 / 15, 1e-9));
      expect(stats.sinceLast, const Duration(hours: 4));
      expect(stats.last!.toLocal(), _at(15, 8));
      expect(dailyCounts(tracker, now, days: 7), [2, 0, 2, 2, 2, 2, 1]);
    });

    test('a sensor averages how long each lasted', () {
      final sensor = _logged(
        newTracker('CGM', const [],
            kind: TrackerKind.sensor, every: const Duration(days: 10)),
        [
          DateTime.utc(2026, 10, 12, 9),
          DateTime.utc(2026, 10, 21, 9),
          DateTime.utc(2026, 10, 31, 9),
          DateTime.utc(2026, 11, 11, 9),
        ],
      );
      final stats = TrackerStats.of(sensor, DateTime.utc(2026, 11, 15, 9));
      expect(stats.averageGap, const Duration(days: 10));
      expect(stats.sinceLast, const Duration(days: 4));
      expect(stats.nextDue, DateTime.utc(2026, 11, 21, 9));
      expect(TrackerStats.of(sensor, now, gaps: 1).averageGap,
          const Duration(days: 11));
      expect(entryGaps(sensor).map((g) => g.gap?.inDays), [11, 10, 9, null]);
    });
  });

  group('parseLogTime', () {
    final now = _at(15, 12);

    test('reads a time today, yesterday or on a date', () {
      expect(parseLogTime('8am', now: now), _at(15, 8));
      expect(parseLogTime('08:15', now: now), _at(15, 8, 15));
      expect(parseLogTime('today 11:59', now: now), _at(15, 11, 59));
      expect(parseLogTime('Yesterday 9pm', now: now), _at(14, 21));
      expect(parseLogTime('2026-11-02 7:30am', now: now), _at(2, 7, 30));
    });

    test('refuses the future and anything else', () {
      for (final text in ['5pm', 'tomorrow 8am', 'yesterday', '', '25:00']) {
        expect(() => parseLogTime(text, now: now), throwsFormatException,
            reason: text);
      }
    });
  });

  group('merge', () {
    const head = '---\nid: met\nname: Metformin\n';
    const path = 'trackers/met.md';
    const a = '- 2026-11-13T08:00:00Z\n', b = '- 2026-11-13T20:00:00Z\n';
    const c = '- 2026-11-14T08:00:00Z\n', d = '- 2026-11-14T20:00:00Z\n';

    TreeMerge merge(String base, String local, String remote) => mergeTrees(
          base: {path: utf8.encode(base)},
          local: {path: utf8.encode(local)},
          remote: {path: utf8.encode(remote)},
          now: DateTime.utc(2026, 11, 15),
        );
    String text(TreeMerge merge) => utf8.decode(merge.files[path]!);

    test('times logged on two devices are all kept, in order', () {
      final result =
          merge('$head---\n$a', '$head---\n$a$d', '$head---\n$a$b$c');
      expect(text(result), '$head---\n$a$b$c$d');
      expect(result.conflicts, isEmpty);
    });

    test('a removal on one side and an addition on the other both apply', () {
      final result =
          merge('$head---\n$a$b', '$head---\n$b', '$head---\n$a$b$c');
      expect(text(result), '$head---\n$b$c');
      expect(result.conflicts, isEmpty);
    });

    test('the same time logged on both sides is kept once', () {
      final result =
          merge('$head---\n$a', '$head---\n$a$b', '$head---\n$a$b$c');
      expect(text(result), '$head---\n$a$b$c');
    });

    test('settings merge key by key, the remote winning a collision', () {
      final result = merge(
        '$head---\n$a',
        '${head}name: Metformin XR\nevery: 12h\n---\n$a$b'
            .replaceFirst('name: Metformin\n', ''),
        '${head}name: Metformin ER\nkind: med\n---\n$a'
            .replaceFirst('name: Metformin\n', ''),
      );
      final tracker = Tracker.parse(text(result));
      expect(tracker.name, 'Metformin ER');
      expect(tracker.every, const Duration(hours: 12));
      expect(tracker.entries, hasLength(2));
      expect(result.conflicts.single.fields, ['name']);
      expect(result.conflicts.single.keptLocal, isFalse);
    });

    test('a tracker logged here and deleted elsewhere is kept', () {
      final result = mergeTrees(
        base: {path: utf8.encode('$head---\n$a')},
        local: {path: utf8.encode('$head---\n$a$b')},
        remote: const {},
        now: DateTime.utc(2026, 11, 15),
      );
      expect(text(result), '$head---\n$a$b');
      expect(result.conflicts.single.kind, ConflictKind.editedAndDeleted);
    });
  });

  test('the workspace loads, saves and deletes trackers', () async {
    final area = MemoryStore().working;
    var workspace = await Workspace.load(area);
    final sensor = newTracker('CGM sensor', const [], kind: TrackerKind.sensor);
    await workspace.saveTracker(sensor.log(_at(14, 9)));
    await workspace.saveTracker(newTracker('Metformin', [sensor]));
    await area.write('trackers/bad.md', utf8.encode('nope'));

    workspace = await Workspace.load(area);
    expect(workspace.trackers.map((t) => t.name), ['CGM sensor', 'Metformin']);
    expect(workspace.tracker('cgm-sensor')!.entries, hasLength(1));
    expect(workspace.problems.keys, ['trackers/bad.md']);

    await workspace.deleteTracker('cgm-sensor');
    expect((await area.readAll()).keys,
        unorderedEquals(['trackers/metformin.md', 'trackers/bad.md']));
  });

  test('two devices logging at once sync without a conflict', () async {
    final github = FakeGitHubClient(repo: const RepoRef('drl', 'geas-data'));
    await initDataRepo(github);
    final one = MemoryStore(), two = MemoryStore();
    Syncer syncer(MemoryStore store, String device) =>
        Syncer(github: github, store: store, device: device);

    final first = await Workspace.load(one.working);
    await first.saveTracker(met.log(_at(14, 8)));
    await syncer(one, 'one').sync();
    await syncer(two, 'two').sync();

    final second = await Workspace.load(two.working);
    await second.saveTracker(second.tracker('metformin')!.log(_at(14, 20)));
    await first.saveTracker(first.tracker('metformin')!.log(_at(15, 8)));
    await syncer(two, 'two').sync();
    final result = await syncer(one, 'one').sync();
    expect(result.conflicts, isEmpty);

    await first.reload();
    expect(first.tracker('metformin')!.entries.map((e) => e.at.toLocal()),
        [_at(14, 8), _at(14, 20), _at(15, 8)]);
  });
}
