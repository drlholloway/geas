import 'package:geas_core/geas_core.dart';
import 'package:test/test.dart';

void main() {
  const file = '''---
id: 01JC8ZQ4R7ME2X5Y9V3T6N0B4K
title: Order 1N914s
list: inbox
tags: [tayda]
priority: high
created: 2026-11-08T23:41:02Z
updated: 2026-11-08T23:41:02Z
completed: null
order:
  vendor: Tayda # the usual
  number: TE-1234567
  status: shipped
  gift: false
  packages:
    - carrier: usps
      tracking: 9400111899223397846185
      eta: 2026-11-14
      status: in-transit
      signed: no
---
Notes.
''';

  group('the order map', () {
    test('parses, keeping every digit of a long tracking number', () {
      final order = Task.parse(file).order!;
      expect(order.vendor, 'Tayda');
      expect(order.number, 'TE-1234567');
      expect(order.status, OrderStatus.shipped);
      expect(order.extra, {'gift': false});
      final package = order.packages.single;
      expect(package.carrier, Carrier.usps);
      expect(package.tracking, '9400111899223397846185');
      expect(package.eta, const LocalDate(2026, 11, 14));
      expect(package.status, PackageStatus.inTransit);
      expect(package.extra, {'signed': 'no'});
    });

    test('a parsed file writes back unchanged', () {
      expect(Task.parse(file).encode(), file);
    });

    test('a change rewrites only that key, keeping comments', () {
      final task = Task.parse(file);
      final delivered = task.copyWith(
        order: task.order!.copyWith(status: OrderStatus.delivered),
      );
      expect(
        delivered.encode(),
        file.replaceFirst('status: shipped', 'status: delivered'),
      );
    });

    test('removing it drops the key; a task without one has none', () {
      final task = Task.parse(file).copyWith(order: null);
      expect(task.encode(), isNot(contains('order')));
      expect(Task.parse(task.encode()).order, isNull);
      final fresh = Task.create(title: 'x', now: DateTime.utc(2026, 11, 9));
      expect(fresh.encode(), isNot(contains('order')));
    });

    test('a new order round-trips', () {
      final task =
          Task.create(title: 'x', now: DateTime.utc(2026, 11, 9)).copyWith(
        order: const Order(vendor: 'Mouser', number: '123')
            .withPackage(Package.track('1Z999AA10123456784')),
      );
      final text = task.encode();
      expect(text, contains('tracking: 1Z999AA10123456784'));
      expect(text, contains('number: "123"'));
      expect(Task.parse(text), task);
    });

    test('bad values are rejected', () {
      String withOrder(String yaml) =>
          file.replaceFirst(RegExp(r'order:[\s\S]*?---'), '$yaml\n---');
      expect(() => Task.parse(withOrder('order: [x]')), throwsFormatException);
      expect(() => Task.parse(withOrder('order:\n  status: lost')),
          throwsFormatException);
      expect(
        () => Task.parse(withOrder('order:\n  packages:\n    - carrier: ups')),
        throwsFormatException,
      );
    });
  });

  group('carriers', () {
    test('detects a carrier from the tracking number', () {
      expect(Carrier.detect('1Z999AA10123456784'), Carrier.ups);
      expect(Carrier.detect('9400 1118 9922 3397 8461 85'), Carrier.usps);
      expect(Carrier.detect('EC123456789US'), Carrier.usps);
      expect(Carrier.detect('123456789012'), Carrier.fedex);
      expect(Carrier.detect('9612345678901234567890'), Carrier.fedex);
      expect(Carrier.detect('1234567890'), Carrier.dhl);
      expect(Carrier.detect('JJD0001234567890'), Carrier.dhl);
      expect(Carrier.detect('ABC'), Carrier.other);
    });

    test('links to each tracking page', () {
      expect('${Carrier.ups.trackingUrl('1Z999AA10123456784')}',
          'https://www.ups.com/track?tracknum=1Z999AA10123456784');
      expect('${Carrier.usps.trackingUrl('9400111899223397846185')}',
          contains('tLabels=9400111899223397846185'));
      expect(Carrier.fedex.trackingUrl('123456789012')!.host, 'www.fedex.com');
      expect(Carrier.dhl.trackingUrl('1234567890')!.queryParameters,
          containsPair('tracking-id', '1234567890'));
      expect(Carrier.other.trackingUrl('x'), isNull);
    });
  });

  test('adding a package marks an order shipped; the same number replaces', () {
    final order = const Order().withPackage(Package.track('123456789012'));
    expect(order.status, OrderStatus.shipped);
    final eta = order.withPackage(
        order.packages.single.copyWith(eta: const LocalDate(2026, 11, 12)));
    expect(eta.packages.single.eta, const LocalDate(2026, 11, 12));
    expect(eta.withoutPackage('123456789012').packages, isEmpty);
  });

  test('in transit goes by the package, then the order', () {
    final p = Package.track('123456789012');
    expect(p.inTransit(OrderStatus.ordered), isFalse);
    expect(p.inTransit(OrderStatus.shipped), isTrue);
    expect(p.inTransit(OrderStatus.delivered), isFalse);
    expect(
      p
          .copyWith(status: PackageStatus.delivered)
          .inTransit(OrderStatus.shipped),
      isFalse,
    );
  });

  group('queries', () {
    final now = DateTime(2026, 11, 9, 12);
    final today = LocalDate.of(now);
    Task ordered(String title, Order order, {bool done = false}) {
      final t = Task.create(title: title, now: now).copyWith(order: order);
      return done ? t.complete(now) : t;
    }

    Order shipping(LocalDate? eta) => const Order().withPackage(
          Package.track('123456789012', eta: eta),
        );

    test('ordersByStatus groups tasks with orders', () {
      final a = ordered('a', const Order());
      final b = ordered('b', shipping(today));
      final c =
          ordered('c', const Order(status: OrderStatus.delivered), done: true);
      final d = ordered('d', shipping(null), done: true); // done, not arrived
      final plain = Task.create(title: 'plain', now: now);
      final groups = ordersByStatus([a, b, c, d, plain]);
      expect(groups[OrderStatus.ordered], [a]);
      expect(groups[OrderStatus.shipped], [b]);
      expect(groups[OrderStatus.delivered], [c]);
    });

    test('packagesArriving: today, late, and this week', () {
      final late = ordered('late', shipping(today.addDays(-1)));
      final due = ordered('today', shipping(today));
      final later = ordered('later', shipping(today.addDays(3)));
      final none = ordered('no eta', shipping(null));
      final tasks = [later, due, none, late];
      expect(
        packagesArriving(tasks, now: now).map((s) => s.task.title),
        ['late', 'today'],
      );
      expect(
        packagesArriving(tasks, now: now, days: 7).map((s) => s.task.title),
        ['late', 'today', 'later'],
      );
    });
  });
}
