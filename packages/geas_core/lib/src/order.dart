import 'package:collection/collection.dart';
import 'package:yaml/yaml.dart';

import 'local_date.dart';
import 'queries.dart';
import 'task.dart';

// The optional `order` map in a task's frontmatter: what was ordered from
// whom, and the packages it ships in. Status is set by hand.

/// Where an order is, set by hand.
enum OrderStatus {
  ordered('ordered', 'Ordered'),
  shipped('shipped', 'Shipped'),
  outForDelivery('out-for-delivery', 'Out for delivery'),
  delivered('delivered', 'Delivered'),
  problem('problem', 'Problem'),
  returned('returned', 'Returned');

  const OrderStatus(this.key, this.label);

  /// As written in the file.
  final String key;
  final String label;

  /// Delivered or returned: nothing more to wait for.
  bool get isDone => this == delivered || this == returned;

  static OrderStatus parse(String text) => values.firstWhere(
        (s) => s.key == text.trim().toLowerCase(),
        orElse: () => throw FormatException(
          'Order status must be one of '
          '${values.map((s) => s.key).join(', ')}, got "$text".',
        ),
      );
}

/// One package's own status, when it differs from the order's.
enum PackageStatus {
  inTransit('in-transit', 'In transit'),
  outForDelivery('out-for-delivery', 'Out for delivery'),
  delivered('delivered', 'Delivered'),
  problem('problem', 'Problem'),
  returned('returned', 'Returned');

  const PackageStatus(this.key, this.label);

  final String key;
  final String label;

  static PackageStatus parse(String text) => values.firstWhere(
        (s) => s.key == text.trim().toLowerCase(),
        orElse: () => throw FormatException(
          'Package status must be one of '
          '${values.map((s) => s.key).join(', ')}, got "$text".',
        ),
      );
}

enum Carrier {
  usps('USPS'),
  ups('UPS'),
  fedex('FedEx'),
  dhl('DHL'),
  other('Other');

  const Carrier(this.label);

  final String label;

  static Carrier parse(String text) => values.firstWhere(
        (c) => c.name == text.trim().toLowerCase(),
        orElse: () => throw FormatException(
          'Carrier must be one of ${values.map((c) => c.name).join(', ')}, '
          'got "$text".',
        ),
      );

  /// The carrier a tracking number's shape points to, or [other].
  static Carrier detect(String tracking) {
    final t = tracking.replaceAll(RegExp(r'\s'), '').toUpperCase();
    if (RegExp(r'^1Z[0-9A-Z]{16}$').hasMatch(t)) return ups;
    if (RegExp(r'^9[1-5]\d{18,20}$').hasMatch(t) ||
        RegExp(r'^[A-Z]{2}\d{9}US$').hasMatch(t)) {
      return usps;
    }
    if (RegExp(r'^(JJD|JD)\d{10,}$').hasMatch(t) ||
        RegExp(r'^\d{10}$').hasMatch(t)) {
      return dhl;
    }
    if (RegExp(r'^(\d{12}|\d{15}|96\d{20})$').hasMatch(t)) return fedex;
    return other;
  }

  /// The carrier's page for [tracking], or null for [other].
  Uri? trackingUrl(String tracking) {
    final t = tracking.replaceAll(RegExp(r'\s'), '');
    return switch (this) {
      usps => Uri.https('tools.usps.com', '/go/TrackConfirmAction', {
          'tLabels': t,
        }),
      ups => Uri.https('www.ups.com', '/track', {'tracknum': t}),
      fedex => Uri.https('www.fedex.com', '/fedextrack/', {'trknbr': t}),
      dhl => Uri.https(
          'www.dhl.com',
          '/us-en/home/tracking/tracking-express.html',
          {'submit': '1', 'tracking-id': t},
        ),
      other => null,
    };
  }
}

const _equality = DeepCollectionEquality();

/// One shipment in an order.
class Package {
  const Package({
    required this.carrier,
    required this.tracking,
    this.eta,
    this.status,
    this.extra = const {},
  });

  /// A package for [tracking], with the carrier detected from its shape
  /// unless [carrier] is given.
  factory Package.track(String tracking, {Carrier? carrier, LocalDate? eta}) {
    final t = tracking.replaceAll(RegExp(r'\s'), '');
    return Package(
        carrier: carrier ?? Carrier.detect(t), tracking: t, eta: eta);
  }

  factory Package._parse(Object? node, int index) {
    if (node is! YamlMap) {
      throw FormatException('Package ${index + 1} in "order" must be a map.');
    }
    final what = 'package ${index + 1}';
    final tracking = _text(node, 'tracking', what);
    if (tracking == null || tracking.isEmpty) {
      throw FormatException('"tracking" is missing from $what.');
    }
    final carrier = _text(node, 'carrier', what);
    final eta = _text(node, 'eta', what);
    final status = _text(node, 'status', what);
    return Package(
      carrier:
          carrier == null ? Carrier.detect(tracking) : Carrier.parse(carrier),
      tracking: tracking,
      eta: eta == null ? null : LocalDate.parse(eta),
      status: status == null ? null : PackageStatus.parse(status),
      extra: _extra(node, const {'carrier', 'tracking', 'eta', 'status'}),
    );
  }

  final Carrier carrier;
  final String tracking;

  /// When it's expected, if known.
  final LocalDate? eta;

  /// Its own status, or null to go by the order's.
  final PackageStatus? status;

  /// Keys Geas doesn't know, kept as they were.
  final Map<String, Object?> extra;

  Uri? get trackingUrl => carrier.trackingUrl(tracking);

  /// Not yet delivered or returned, going by its own status if it has one.
  bool inTransit(OrderStatus order) => switch (status) {
        null => !order.isDone && order != OrderStatus.ordered,
        PackageStatus.delivered || PackageStatus.returned => false,
        _ => true,
      };

  /// Pass null for [eta] or [status] to clear them.
  Package copyWith({
    Carrier? carrier,
    Object? eta = _keep,
    Object? status = _keep,
  }) =>
      Package(
        carrier: carrier ?? this.carrier,
        tracking: tracking,
        eta: identical(eta, _keep) ? this.eta : eta as LocalDate?,
        status:
            identical(status, _keep) ? this.status : status as PackageStatus?,
        extra: extra,
      );

  Map<String, Object?> toYaml() => {
        'carrier': carrier.name,
        'tracking': tracking,
        if (eta != null) 'eta': '$eta',
        if (status != null) 'status': status!.key,
        ...extra,
      };

  @override
  bool operator ==(Object other) =>
      other is Package &&
      other.carrier == carrier &&
      other.tracking == tracking &&
      other.eta == eta &&
      other.status == status &&
      _equality.equals(other.extra, extra);

  @override
  int get hashCode =>
      Object.hash(carrier, tracking, eta, status, _equality.hash(extra));

  @override
  String toString() => 'Package(${carrier.name}, $tracking)';
}

const _keep = Object();

/// What was ordered from whom, and how it's getting here.
class Order {
  const Order({
    this.vendor,
    this.number,
    this.url,
    this.status = OrderStatus.ordered,
    this.packages = const [],
    this.extra = const {},
  });

  /// Parses the `order` value from frontmatter, throwing [FormatException]
  /// if it isn't a valid order.
  factory Order.parse(Object? node) {
    if (node is! YamlMap) {
      throw const FormatException('"order" must be a map.');
    }
    const what = 'order';
    final status = _text(node, 'status', what);
    final packages = node['packages'];
    if (packages != null && packages is! YamlList) {
      throw const FormatException('"packages" in "order" must be a list.');
    }
    return Order(
      vendor: _text(node, 'vendor', what),
      number: _text(node, 'number', what),
      url: _text(node, 'url', what),
      status: status == null ? OrderStatus.ordered : OrderStatus.parse(status),
      packages: [
        if (packages is YamlList)
          for (final (i, p) in packages.indexed) Package._parse(p, i),
      ],
      extra: _extra(
        node,
        const {'vendor', 'number', 'url', 'status', 'packages'},
      ),
    );
  }

  final String? vendor;

  /// The vendor's order number.
  final String? number;

  /// The vendor's page for the order.
  final String? url;
  final OrderStatus status;
  final List<Package> packages;

  /// Keys Geas doesn't know, kept as they were.
  final Map<String, Object?> extra;

  /// Packages not yet delivered or returned.
  List<Package> get inTransit => [
        for (final p in packages)
          if (p.inTransit(status)) p
      ];

  /// Pass null for [vendor], [number] or [url] to clear them.
  Order copyWith({
    Object? vendor = _keep,
    Object? number = _keep,
    Object? url = _keep,
    OrderStatus? status,
    List<Package>? packages,
  }) =>
      Order(
        vendor: identical(vendor, _keep) ? this.vendor : vendor as String?,
        number: identical(number, _keep) ? this.number : number as String?,
        url: identical(url, _keep) ? this.url : url as String?,
        status: status ?? this.status,
        packages: packages ?? this.packages,
        extra: extra,
      );

  /// With [package] added, or replacing the one with the same tracking
  /// number. Adding a package to an order still at [OrderStatus.ordered]
  /// marks it shipped.
  Order withPackage(Package package) {
    final index = packages.indexWhere((p) => p.tracking == package.tracking);
    return copyWith(
      packages: index < 0
          ? [...packages, package]
          : ([...packages]..[index] = package),
      status: index < 0 && status == OrderStatus.ordered
          ? OrderStatus.shipped
          : status,
    );
  }

  Order withoutPackage(String tracking) => copyWith(
        packages: [
          for (final p in packages)
            if (p.tracking != tracking) p
        ],
      );

  /// The value for the `order` key, in the file's key order.
  Map<String, Object?> toYaml() => {
        if (vendor != null) 'vendor': vendor,
        if (number != null) 'number': number,
        if (url != null) 'url': url,
        'status': status.key,
        if (packages.isNotEmpty)
          'packages': [for (final p in packages) p.toYaml()],
        ...extra,
      };

  @override
  bool operator ==(Object other) =>
      other is Order &&
      other.vendor == vendor &&
      other.number == number &&
      other.url == url &&
      other.status == status &&
      const ListEquality<Package>().equals(other.packages, packages) &&
      _equality.equals(other.extra, extra);

  @override
  int get hashCode => Object.hash(vendor, number, url, status,
      Object.hashAll(packages), _equality.hash(extra));

  @override
  String toString() => 'Order(${status.key}, $vendor $number)';
}

/// A scalar as it's written, so a long tracking number YAML would read as a
/// float keeps every digit.
String? _text(YamlMap map, String key, String what) {
  final node = map.nodes[key];
  if (node == null || node.value == null) return null;
  if (node is! YamlScalar) {
    throw FormatException('"$key" in $what must be a single value.');
  }
  final value = node.value;
  if (value is String) return value;
  return node.span.text.trim();
}

/// The keys of [map] not in [known], as plain Dart values.
Map<String, Object?> _extra(YamlMap map, Set<String> known) => {
      for (final MapEntry(:key, :value) in map.entries)
        if (!known.contains(key)) '$key': _plain(value),
    };

Object? _plain(Object? value) => switch (value) {
      YamlMap() => {
          for (final MapEntry(:key, :value) in value.entries)
            '$key': _plain(value),
        },
      YamlList() => [for (final v in value) _plain(v)],
      _ => value,
    };

/// Tasks tracking an order, by order status, in the default order. Open
/// tasks count whatever their status; completed ones only once the order
/// is delivered or returned.
Map<OrderStatus, List<Task>> ordersByStatus(Iterable<Task> tasks) {
  final groups = {for (final s in OrderStatus.values) s: <Task>[]};
  for (final task in tasks.toList()..sort(compareByDue)) {
    final order = task.order;
    if (order == null) continue;
    if (task.isCompleted && !order.status.isDone) continue;
    groups[order.status]!.add(task);
  }
  return groups;
}

/// A package and the task whose order it's in.
typedef Shipment = ({Task task, Package package});

/// Packages still on their way on open tasks, expected within [days] days
/// from today (1 for today only), including late ones, soonest first.
List<Shipment> packagesArriving(
  Iterable<Task> tasks, {
  required DateTime now,
  int days = 1,
}) {
  final last = LocalDate.of(now.toLocal()).addDays(days - 1);
  final shipments = <Shipment>[
    for (final task in tasks)
      if (!task.isCompleted && task.order != null)
        for (final package in task.order!.inTransit)
          if (package.eta != null && !package.eta!.isAfter(last))
            (task: task, package: package),
  ];
  return shipments..sort((a, b) => a.package.eta!.compareTo(b.package.eta!));
}
