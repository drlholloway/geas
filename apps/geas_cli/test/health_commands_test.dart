import 'package:geas_core/geas_core.dart';
import 'package:test/test.dart';

import 'harness.dart';

void main() {
  late Harness geas;

  setUp(() async {
    geas = await Harness.create();
    await geas.init();
  });
  tearDown(() => geas.dispose());

  Future<String> run(List<String> args) async {
    expect(await geas(args), 0, reason: '${geas.err}');
    return '${geas.out}';
  }

  Tracker remote(String id) => Tracker.parse(geas.remote('trackers/$id.md')!);

  test('add, log and list a medication', () async {
    expect(await run(['health']), contains('Nothing is tracked yet'));
    expect(await run(['health', 'add', 'Metformin']),
        contains('Tracking Metformin (metformin)'));
    expect(await run(['health']), contains('Metformin  nothing logged'));

    await run(['log', 'met', '--at', 'yesterday 8pm', '--note', 'with dinner']);
    await run(['take', 'Metformin', '--at', '8am']);
    expect(
      await run(['log', 'metformin']),
      'Taken Metformin at 2026-11-09 12:00; taken 0 min ago, 2 today, '
      '1.5 a day this week.\n',
    );
    final tracker = remote('metformin');
    expect(tracker.entries.map((e) => e.at.toLocal()), [
      DateTime(2026, 11, 8, 20),
      DateTime(2026, 11, 9, 8),
      DateTime(2026, 11, 9, 12),
    ]);
    expect(tracker.entries.first.note, 'with dinner');

    geas.now = DateTime(2026, 11, 9, 16);
    expect(await run(['health']),
        contains('Metformin  taken 4 h ago, 2 today, 1.5 a day this week'));
    final shown = await run(['health', 'show', 'met', '-n', '2']);
    expect(shown, contains('Metformin (metformin), medication\n'));
    expect(
        shown, contains('Taken 3 times since Sun 2026-11-08; last 4 h ago.'));
    expect(shown, contains('Today 2, 7 days 3 (1.5 a day)'));
    expect(shown, contains('  2026-11-09 12:00  after 4 h\n'));
    expect(shown, contains('  2026-11-09 08:00  after 12 h\n'));
    expect(shown, isNot(contains('with dinner')));
  });

  test('a sensor shows its day and how long each lasted', () async {
    await run([
      'health',
      'add',
      'CGM',
      'sensor',
      '--kind',
      'sensor',
      '--every',
      '10d'
    ]);
    await run(['log', 'cgm', '--at', '2026-10-20 09:00']);
    await run(['log', 'cgm', '--at', '2026-10-30 09:00']);
    await run(['log', 'cgm', '--at', '2026-11-05 12:00']);
    expect(remote('cgm-sensor').every, const Duration(days: 10));
    expect(
      await run(['health']),
      contains('replaced 4 days ago, day 5 of 10, lasts 8.1 days on average'),
    );
    expect(await run(['health', 'show', 'cgm']),
        contains('Next due 2026-11-15 12:00.'));
  });

  test('undo removes the latest time', () async {
    await run(['health', 'add', 'Metformin']);
    await run(['log', 'met', '--at', '8am']);
    await run(['log', 'met']);
    expect(await run(['log', 'met', '--undo']),
        'Removed Metformin at 2026-11-09 12:00.\n');
    expect(remote('metformin').entries.single.at.toLocal(),
        DateTime(2026, 11, 9, 8));
  });

  test('mistakes are reported', () async {
    expect(await geas(['log', 'met']), 1);
    expect('${geas.err}', contains('Nothing is tracked yet'));
    await run(['health', 'add', 'Metformin']);
    await run(['health', 'add', 'Melatonin']);
    expect(await geas(['log', 'me']), 1);
    expect('${geas.err}', contains('More than one matches "me"'));
    expect(await geas(['log', 'met', '--at', '5pm']), 1);
    expect('${geas.err}', contains('hasn\'t happened yet'));
    expect(await geas(['health', 'add', 'metformin']), 1);
    expect(await geas(['health', 'add', 'X', '--every', 'daily']), 1);
    expect(await geas(['health', 'add', 'X', '--kind', 'pill']), 64);
  });

  test('move reorders what\'s tracked', () async {
    await run(['health', 'add', 'Metformin']);
    await run(['health', 'add', 'CGM', 'sensor', '--kind', 'sensor']);
    await run(['health', 'add', 'Vitamin D']);
    expect(await run(['health', 'move', 'vitamin', '1']),
        'Vitamin D, Metformin, CGM sensor\n');
    expect(await run(['health', 'move', 'met', '9']),
        'Vitamin D, CGM sensor, Metformin\n');
    expect(remote('metformin').order, 3);
    expect(remote('vitamin-d').order, 1);
    expect(await geas(['health', 'move', 'met', 'first']), 64);
  });

  test('rm asks before dropping a log', () async {
    await run(['health', 'add', 'Metformin']);
    await run(['log', 'met']);
    expect(await geas(['health', 'rm', 'met']), 1);
    expect(geas.remote('trackers/metformin.md'), isNotNull);
    geas.confirmAnswer = true;
    await run(['health', 'rm', 'met']);
    expect(geas.remote('trackers/metformin.md'), isNull);
  });
}
