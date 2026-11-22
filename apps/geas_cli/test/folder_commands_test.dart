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

  test('folders hold lists, filters and trackers', () async {
    expect(await run(['folders']), contains('No folders yet'));
    await run(['lists', 'add', 'Meds']);
    await run(['add', 'Refill metformin #refill ^meds']);
    await run(['find', '--save', 'Refills', '#refill']);
    await run(['health', 'add', 'Metformin']);
    expect(await run(['folders', 'add', 'Health']),
        'Added the folder Health (health).\n');

    final put = await run(
        ['folders', 'put', 'health', 'meds', 'Refills', 'tracker:metformin']);
    expect(put, contains('Put Meds in Health.'));
    expect(put, contains('Put Metformin in Health.'));
    expect(TaskList.parse(geas.remote('lists/meds.yaml')!).folder, 'health');
    expect(SavedFilter.parse(geas.remote('filters/refills.yaml')!).folder,
        'health');
    expect(
        Tracker.parse(geas.remote('trackers/metformin.md')!).folder, 'health');
    expect(
      await run(['folders']),
      'Health (health)\n'
      '  list     Meds\n'
      '  filter   Refills\n'
      '  tracker  Metformin\n',
    );

    await run(['folders', 'take', 'refills']);
    expect(
        SavedFilter.parse(geas.remote('filters/refills.yaml')!).folder, isNull);
    await run(['folders', 'rename', 'health', 'Body']);
    expect(await run(['folders']), startsWith('Body (health)\n'));

    expect(await run(['folders', 'rm', 'body']),
        contains('what was in it (2) is in no folder now'));
    expect(geas.remote('folders/health.yaml'), isNull);
    expect(TaskList.parse(geas.remote('lists/meds.yaml')!).folder, isNull);
    expect(Tracker.parse(geas.remote('trackers/metformin.md')!).folder, isNull);
  });

  test('mistakes are reported', () async {
    await run(['folders', 'add', 'Health']);
    await run(['lists', 'add', 'Metformin']);
    await run(['health', 'add', 'Metformin']);
    expect(await geas(['folders', 'add', 'health']), 1);
    expect(await geas(['folders', 'put', 'nope', 'metformin']), 1);
    expect('${geas.err}', contains('No folder "nope"'));
    expect(await geas(['folders', 'put', 'health', 'metformin']), 1);
    expect('${geas.err}',
        contains('Say which: list:metformin or tracker:metformin.'));
    expect(await geas(['folders', 'put', 'health', 'inbox']), 1);
    expect('${geas.err}', contains('No list, filter or tracker'));
    expect(await geas(['folders', 'put', 'health']), 64);
    await run(['folders', 'put', 'health', 'list:metformin']);
  });

  test('folders nest, and are put in order', () async {
    await run(['folders', 'add', 'Health']);
    await run(['folders', 'add', 'Diabetes']);
    await run(['folders', 'add', 'Builds']);
    await run(['lists', 'add', 'Meds']);
    await run(['folders', 'put', 'diabetes', 'meds']);

    expect(await run(['folders', 'nest', 'diabetes', 'health']),
        'Put Diabetes inside Health.\n');
    expect(
        Folder.parse(geas.remote('folders/diabetes.yaml')!).parent, 'health');
    expect(
      await run(['folders']),
      'Health (health)\n'
      '  Diabetes (diabetes)\n'
      '    list     Meds\n'
      'Builds (builds)\n'
      '  (empty)\n',
    );
    expect(await geas(['folders', 'nest', 'health', 'diabetes']), 1);
    expect('${geas.err}', contains('can\'t go inside itself'));

    expect(await run(['folders', 'move', 'builds', '1']), 'Builds, Health\n');
    expect(await run(['folders']), startsWith('Builds (builds)\n'));

    // Removing a folder moves what was in it up a level.
    await run(['folders', 'nest', 'health', 'builds']);
    await run(['folders', 'rm', 'health']);
    expect(
        Folder.parse(geas.remote('folders/diabetes.yaml')!).parent, 'builds');
    await run(['folders', 'unnest', 'diabetes']);
    expect(Folder.parse(geas.remote('folders/diabetes.yaml')!).parent, isNull);
  });
}
