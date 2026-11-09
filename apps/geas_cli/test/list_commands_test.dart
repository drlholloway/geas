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

  test('lists shows the inbox with open counts', () async {
    expect(await geas(['add', 'one']), 0);
    expect(await geas(['lists']), 0);
    expect('${geas.out}', '  inbox  Inbox  1 open\n');
  });

  test('lists add makes an id from the name, and pushes', () async {
    expect(
        await geas(['lists', 'add', 'Pedal Builds!', '--color', '#a33b3b']), 0);
    expect('${geas.out}', 'Added the list Pedal Builds! (pedal-builds).\n');
    final list = TaskList.parse(geas.remote('lists/pedal-builds.yaml')!);
    expect(list.name, 'Pedal Builds!');
    expect(list.color, '#a33b3b');
    expect(list.order, 1);

    expect(await geas(['lists', 'add', 'pedal builds!']), 1);
    expect(geas.err.toString(), contains('already a list'));
    expect(await geas(['lists', 'add', 'Pedal-Builds']), 0);
    expect(geas.remote('lists/pedal-builds-2.yaml'), isNotNull);
    expect(await geas(['lists', 'add', 'x', '--color', 'red']), 64);
    expect(await geas(['lists', '--color', '#ffffff']), 64);
  });

  test('lists rename keeps the id', () async {
    expect(await geas(['lists', 'add', 'Pedals']), 0);
    expect(await geas(['lists', 'rename', 'pedals', 'Pedal', 'builds']), 0);
    expect('${geas.out}', 'Renamed Pedals to Pedal builds.\n');
    expect(
        TaskList.parse(geas.remote('lists/pedals.yaml')!).name, 'Pedal builds');

    expect(await geas(['lists', 'rename', 'inbox', 'In']), 0);
    expect(geas.remote('lists/inbox.yaml'), isNotNull);
  });

  test('lists rm moves its tasks to the inbox', () async {
    expect(await geas(['lists', 'add', 'Pedals']), 0);
    expect(await geas(['add', 'Order parts', '-l', 'pedals']), 0);
    expect(await geas(['lists', 'rm', 'Pedals']), 0);
    expect(
        '${geas.out}', 'Removed the list Pedals; moved 1 task to the inbox.\n');
    expect(geas.remote('lists/pedals.yaml'), isNull);
    expect(geas.remoteTask('Order parts').list, inboxId);

    expect(await geas(['lists', 'rm', 'inbox']), 1);
    expect(await geas(['lists', 'frobnicate']), 64);
  });

  test('tags counts open tasks', () async {
    expect(await geas(['tags']), 0);
    expect('${geas.out}', 'No tags.\n');
    expect(await geas(['add', 'a', '-t', 'home,Errands']), 0);
    expect(await geas(['add', 'b', '-t', 'home']), 0);
    expect(await geas(['add', 'c', '-t', 'gone']), 0);
    final done = RegExp(r'^Added (\S+)').firstMatch('${geas.out}')![1]!;
    expect(await geas(['done', done]), 0);
    expect(await geas(['tags']), 0);
    expect('${geas.out}', '  #Errands  1\n  #home     2\n');
  });
}
