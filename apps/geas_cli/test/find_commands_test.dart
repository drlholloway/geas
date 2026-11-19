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

  Future<void> seed() async {
    await run(['lists', 'add', 'Pedals']);
    await run(['add', 'Order 1N914s #tayda ^pedals !high today']);
    await run(['add', 'Order knobs #tayda ^pedals']);
    await run(['add', 'Call the dentist !low']);
    final out = await run(['add', 'Solder the fuzz ^pedals']);
    await run(['done', RegExp(r'^Added (\S+) ').firstMatch(out)![1]!]);
  }

  test('find searches by words, tags, lists, priority and due date', () async {
    await seed();
    var out = await run(['find', 'order']);
    expect(out, contains('Order 1N914s'));
    expect(out, contains('Order knobs'));
    expect(out, isNot(contains('dentist')));

    out = await run(['find', '#tayda', 'due:today']);
    expect(out.trim().split('\n'), hasLength(1));
    expect(out, contains('today'));
    expect(out, contains('!!!'));

    expect(await run(['search', '^pedals', 'is:done']),
        contains('done  Solder the fuzz'));
    expect(await run(['find', 'zebra']), 'No tasks match.\n');
    expect(await geas(['find']), 64);
  });

  test('a search can be saved, run again, listed and removed', () async {
    await seed();
    expect(await run(['filters']), contains('No filters saved yet'));
    final saved =
        await run(['find', '--save', 'Tayda orders', '#tayda', 'order']);
    expect(saved, contains('Saved the filter Tayda orders (tayda-orders).'));
    expect(saved, contains('Order knobs'));
    expect(geas.remote('filters/tayda-orders.yaml'),
        contains('query: "#tayda order"'));

    expect(await run(['find', '-f', 'tayda orders']), contains('Order knobs'));
    expect(await run(['filters']),
        contains('tayda-orders  Tayda orders    2  #tayda order'));
    expect(await geas(['find', '--save', 'tayda orders', 'x']), 1);
    expect(await geas(['find', '-f', 'nope']), 1);
    expect('${geas.err}', contains('No filter "nope"'));

    await run(['filters', 'rm', 'tayda-orders']);
    expect(geas.remote('filters/tayda-orders.yaml'), isNull);
  });
}
