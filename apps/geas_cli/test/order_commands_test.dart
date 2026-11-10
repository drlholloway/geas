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

  Future<String> add(String title) async {
    expect(await geas(['add', title]), 0, reason: '${geas.err}');
    return RegExp(r'^Added (\S+) ').firstMatch('${geas.out}')![1]!;
  }

  Future<String> run(List<String> args) async {
    expect(await geas(args), 0, reason: '${geas.err}');
    return '${geas.out}';
  }

  test('order sets the vendor, number and status', () async {
    final id = await add('Order 1N914s');
    expect(
      await run(['order', id, '--vendor', 'Tayda', '--number', 'TE-1']),
      'Order 1N914s: Ordered from Tayda #TE-1.\n',
    );
    await run(['order', id, '--status', 'out for delivery']);
    final order = geas.remoteTask('Order 1N914s').order!;
    expect(order.vendor, 'Tayda');
    expect(order.status, OrderStatus.outForDelivery);

    expect(await run(['order', id]), contains('Out for delivery from Tayda'));
    await run(['order', id, '--number', '']);
    expect(geas.remoteTask('Order 1N914s').order!.number, isNull);

    await run(['order', id, '--remove']);
    expect(geas.remoteTask('Order 1N914s').order, isNull);
  });

  test('a bad status is an error', () async {
    final id = await add('x');
    expect(await geas(['order', id, '--status', 'lost']), 1);
    expect('${geas.err}', contains('Order status must be one of'));
  });

  test('track adds packages, detecting the carrier', () async {
    final id = await add('Order pots');
    final out = await run(['track', id, '1Z999AA10123456784', '--eta', 'wed']);
    expect(out, contains('Tracking UPS 1Z999AA10123456784'));
    expect(out, contains('https://www.ups.com/track?tracknum='));
    var order = geas.remoteTask('Order pots').order!;
    expect(order.status, OrderStatus.shipped);
    expect(order.packages.single.carrier, Carrier.ups);
    expect(order.packages.single.eta, const LocalDate(2026, 11, 11));

    await run(['track', id, '1Z999AA10123456784', '--status', 'delivered']);
    await run(['track', id, '9400 1118 9922 3397 8461 85']);
    order = geas.remoteTask('Order pots').order!;
    expect(order.packages.map((p) => p.carrier), [Carrier.ups, Carrier.usps]);
    expect(order.packages.first.status, PackageStatus.delivered);

    await run(['track', id, '1Z999AA10123456784', '--remove']);
    expect(geas.remoteTask('Order pots').order!.packages.single.tracking,
        '9400111899223397846185');
  });

  test('orders groups by status and hides finished ones', () async {
    final a = await add('Order diodes');
    final b = await add('Order knobs');
    final c = await add('Order enclosure');
    await run(['order', a, '--vendor', 'Tayda']);
    await run(['track', b, '123456789012']);
    await run(['order', c, '--status', 'delivered']);

    final out = await run(['orders']);
    expect(out, contains('Ordered\n'));
    expect(out, contains('Order diodes  Tayda'));
    expect(out, contains('Shipped\n'));
    expect(out, contains('FedEx 123456789012'));
    expect(out, isNot(contains('Order enclosure')));
    expect(await run(['orders', '--all']), contains('Delivered\n'));
    expect(await run(['show', b]), contains('order     Shipped'));
  });
}
