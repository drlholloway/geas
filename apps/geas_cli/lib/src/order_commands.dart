import 'package:geas_core/geas_core.dart';

import 'command.dart';
import 'context.dart';
import 'output.dart';
import 'session.dart';

/// The order and its packages as indented lines, for `show` and `order`.
List<String> orderLines(Order order, DateTime now) => [
      [
        order.status.label,
        if (order.vendor != null) 'from ${order.vendor}',
        if (order.number != null) '#${order.number}',
      ].join(' '),
      if (order.url != null) order.url!,
      for (final p in order.packages) packageLine(p, now),
    ];

String packageLine(Package p, DateTime now) => [
      '${p.carrier.label} ${p.tracking}',
      if (p.status != null) p.status!.label.toLowerCase(),
      if (p.eta != null) 'eta ${dueLabel(Due.date(p.eta!), now)}',
      if (p.trackingUrl != null) '${p.trackingUrl}',
    ].join('  ');

T _parse<T>(T Function(String) parse, String text) {
  try {
    return parse(text.replaceAll(' ', '-'));
  } on FormatException catch (e) {
    throw CliException(e.message);
  }
}

class OrderCommand extends GeasCommand {
  OrderCommand(super.context) {
    argParser
      ..addOption('vendor', help: 'Who it\'s from.')
      ..addOption('number', help: 'The vendor\'s order number.')
      ..addOption('url', help: 'The vendor\'s page for the order.')
      ..addOption('status',
          help: 'ordered, shipped, out-for-delivery, delivered, problem or '
              'returned.')
      ..addFlag('remove',
          negatable: false, help: 'Stop tracking an order on this task.');
  }

  @override
  final name = 'order';

  @override
  final description = 'Track an order on a task, or show or change it.';

  @override
  String get invocation => 'geas order <id> [--vendor <name>] '
      '[--number <n>] [--url <url>] [--status <status>] [--remove]';

  @override
  Future<int> run() async {
    if (rest.length != 1) usageException('Give one task id.');
    final args = argResults!;
    final session = await openSession();
    await session.pull();
    final task = session.resolveTask(rest.single);
    final now = context.clock();

    if (args['remove'] as bool) {
      if (task.order == null) {
        throw CliException('${session.shortId(task.id)} has no order.');
      }
      await session.workspace
          .saveTask(task.copyWith(order: null, updated: now), now: now);
      out.writeln('Stopped tracking the order on ${task.title}.');
      await session.push();
      return 0;
    }

    String? option(String name) {
      final value = (args[name] as String?)?.trim();
      return value == null ? null : (value.isEmpty ? '' : value);
    }

    final vendor = option('vendor'),
        number = option('number'),
        url = option('url'),
        status = option('status');
    final changing = [vendor, number, url, status].any((v) => v != null);
    if (!changing) {
      final order = task.order;
      out.writeln(task.title);
      if (order == null) {
        out.writeln('  No order. Add one with --vendor, --number or '
            '`geas track`.');
      } else {
        orderLines(order, now).forEach((l) => out.writeln('  $l'));
      }
      return 0;
    }

    final before = task.order ?? const Order();
    // An empty value clears the field.
    final order = before.copyWith(
      vendor: vendor == null ? before.vendor : (vendor.isEmpty ? null : vendor),
      number: number == null ? before.number : (number.isEmpty ? null : number),
      url: url == null ? before.url : (url.isEmpty ? null : url),
      status: status == null ? null : _parse(OrderStatus.parse, status),
    );
    await session.workspace
        .saveTask(task.copyWith(order: order, updated: now), now: now);
    out.writeln('${task.title}: ${orderLines(order, now).first}.');
    await session.push();
    return 0;
  }
}

class TrackCommand extends GeasCommand {
  TrackCommand(super.context) {
    argParser
      ..addOption('carrier',
          help: 'usps, ups, fedex, dhl or other (default: from the number).')
      ..addOption('eta', help: 'When it\'s expected: today, fri, 2026-11-14.')
      ..addOption('status',
          help: 'in-transit, out-for-delivery, delivered, problem or '
              'returned.')
      ..addFlag('remove', negatable: false, help: 'Remove this package.');
  }

  @override
  final name = 'track';

  @override
  final description = 'Add a package to a task\'s order by its tracking '
      'number, or change or remove it. Starts an order if there isn\'t one.';

  @override
  String get invocation => 'geas track <id> <tracking-number> '
      '[--carrier <carrier>] [--eta <date>] [--status <status>] [--remove]';

  @override
  Future<int> run() async {
    if (rest.length < 2) {
      usageException('Give a task id and a tracking number.');
    }
    final args = argResults!;
    final session = await openSession();
    await session.pull();
    final task = session.resolveTask(rest.first);
    final tracking = rest.skip(1).join().replaceAll(RegExp(r'\s'), '');
    final now = context.clock();
    final before = task.order ?? const Order();
    final existing =
        before.packages.where((p) => p.tracking == tracking).firstOrNull;

    final Order order;
    if (args['remove'] as bool) {
      if (existing == null) {
        throw CliException('${task.title} has no package $tracking.');
      }
      order = before.withoutPackage(tracking);
      out.writeln('Removed $tracking from ${task.title}.');
    } else {
      final carrierText = args['carrier'] as String?;
      final etaText = args['eta'] as String?;
      final statusText = args['status'] as String?;
      var package = existing ??
          Package.track(
            tracking,
            carrier:
                carrierText == null ? null : _parse(Carrier.parse, carrierText),
          );
      if (existing != null && carrierText != null) {
        package = package.copyWith(carrier: _parse(Carrier.parse, carrierText));
      }
      if (etaText != null) {
        try {
          package =
              package.copyWith(eta: parseDueInput(etaText, now: now).localDate);
        } on FormatException catch (e) {
          throw CliException('--eta: ${e.message}');
        }
      }
      if (statusText != null) {
        package =
            package.copyWith(status: _parse(PackageStatus.parse, statusText));
      }
      order = before.withPackage(package);
      out.writeln('${existing == null ? 'Tracking' : 'Updated'} '
          '${packageLine(package, now)} on ${task.title}.');
    }
    await session.workspace
        .saveTask(task.copyWith(order: order, updated: now), now: now);
    await session.push();
    return 0;
  }
}

class OrdersCommand extends GeasCommand {
  OrdersCommand(super.context) {
    argParser.addFlag('all',
        negatable: false, help: 'Include delivered and returned orders.');
  }

  @override
  final name = 'orders';

  @override
  final description = 'Show orders by status, with their packages and '
      'tracking links.';

  @override
  String get invocation => 'geas orders [--all]';

  @override
  Future<int> run() async {
    if (rest.isNotEmpty) usageException('orders takes no arguments.');
    final all = argResults!['all'] as bool;
    final session = await openSession();
    await session.pull();
    final now = context.clock();
    final groups = ordersByStatus(session.workspace.tasks);
    var shown = false;
    for (final status in OrderStatus.values) {
      final tasks = groups[status]!;
      if (tasks.isEmpty || (status.isDone && !all)) continue;
      if (shown) out.writeln();
      shown = true;
      out.writeln(status.label);
      for (final task in tasks) {
        _writeTask(session, task, now);
      }
    }
    if (!shown) out.writeln(all ? 'No orders.' : 'No open orders.');
    return 0;
  }

  void _writeTask(Session session, Task task, DateTime now) {
    final order = task.order!;
    out.writeln([
      '  ${session.shortId(task.id)}',
      task.title,
      if (order.vendor != null) order.vendor!,
      if (order.number != null) '#${order.number}',
    ].join('  '));
    for (final p in order.packages) {
      out.writeln('      ${packageLine(p, now)}');
    }
  }
}
