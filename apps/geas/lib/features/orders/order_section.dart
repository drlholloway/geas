import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';

import '../../state/environment.dart';
import '../../state/store.dart';
import '../tasks/due_label.dart';

/// The order part of the task sheet: vendor, number and status, and the
/// packages with their tracking links. A button starts one if the task has
/// none.
class OrderSection extends ConsumerStatefulWidget {
  const OrderSection({super.key, required this.task});

  final Task task;

  @override
  ConsumerState<OrderSection> createState() => _OrderSectionState();
}

class _OrderSectionState extends ConsumerState<OrderSection> {
  late final _vendor = TextEditingController(text: widget.task.order?.vendor);
  late final _number = TextEditingController(text: widget.task.order?.number);
  late final _url = TextEditingController(text: widget.task.order?.url);
  final _tracking = TextEditingController();

  @override
  void dispose() {
    for (final c in [_vendor, _number, _url, _tracking]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Changes the order as it is now on the task.
  void _edit(Order Function(Order order) change) => ref
      .read(taskStoreProvider.notifier)
      .edit(
        widget.task.id,
        (t) => t.copyWith(order: change(t.order ?? const Order())),
      );

  static String? _orNull(String text) =>
      text.trim().isEmpty ? null : text.trim();

  void _setStatus(OrderStatus status) =>
      _edit((o) => o.copyWith(status: status));

  void _addPackage(String text) {
    final tracking = text.replaceAll(RegExp(r'\s'), '');
    if (tracking.isEmpty) return;
    _edit((o) => o.withPackage(Package.track(tracking)));
    _tracking.clear();
  }

  Future<void> _pickEta(Package package) async {
    final now = ref.read(clockProvider)();
    final initial = package.eta ?? LocalDate.of(now);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2, 12, 31),
    );
    if (picked == null) return;
    _edit((o) => o.withPackage(package.copyWith(eta: LocalDate.of(picked))));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = widget.task.order;
    if (order == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _edit((o) => o),
          icon: const Icon(Icons.local_shipping_outlined),
          label: const Text('Track an order'),
        ),
      );
    }
    final now = ref.watch(clockProvider)();
    final env = ref.read(environmentProvider);

    InputDecoration field(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      border: const OutlineInputBorder(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.local_shipping_outlined,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text('Order', style: theme.textTheme.titleSmall)),
            PopupMenuButton<OrderStatus>(
              tooltip: 'Order status',
              initialValue: order.status,
              onSelected: _setStatus,
              itemBuilder: (_) => [
                for (final s in OrderStatus.values)
                  PopupMenuItem(value: s, child: Text(s.label)),
              ],
              child: Chip(label: Text(order.status.label)),
            ),
            IconButton(
              tooltip: 'Stop tracking the order',
              onPressed: () => ref
                  .read(taskStoreProvider.notifier)
                  .edit(widget.task.id, (t) => t.copyWith(order: null)),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        // Delivered: offer to finish the task too.
        if (order.status == OrderStatus.delivered && !widget.task.isCompleted)
          Card(
            color: theme.colorScheme.secondaryContainer,
            margin: const EdgeInsets.only(top: 4, bottom: 4),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(
                children: [
                  const Expanded(child: Text('Delivered. Mark the task done?')),
                  TextButton(
                    onPressed: () => ref
                        .read(taskStoreProvider.notifier)
                        .edit(
                          widget.task.id,
                          (t) => t.complete(ref.read(clockProvider)()),
                        ),
                    child: const Text('Mark done'),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _vendor,
                decoration: field('Vendor'),
                onChanged: (v) => _edit((o) => o.copyWith(vendor: _orNull(v))),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _number,
                decoration: field('Order number'),
                onChanged: (v) => _edit((o) => o.copyWith(number: _orNull(v))),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: field('Order page').copyWith(
            suffixIcon: order.url == null
                ? null
                : IconButton(
                    tooltip: 'Open the order page',
                    onPressed: () {
                      final uri = Uri.tryParse(order.url!);
                      if (uri != null) env.openUrl(uri);
                    },
                    icon: const Icon(Icons.open_in_new, size: 18),
                  ),
          ),
          onChanged: (v) => _edit((o) => o.copyWith(url: _orNull(v))),
        ),
        const SizedBox(height: 8),
        for (final p in order.packages)
          _PackageRow(
            key: ValueKey(p.tracking),
            package: p,
            inTransit: p.inTransit(order.status),
            now: now,
            onOpen: p.trackingUrl == null
                ? null
                : () => env.openUrl(p.trackingUrl!),
            onEta: () => _pickEta(p),
            onRemove: () => _edit((o) => o.withoutPackage(p.tracking)),
          ),
        TextField(
          controller: _tracking,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            border: InputBorder.none,
            icon: Icon(Icons.add, size: 20),
            hintText: 'Paste a tracking number',
          ),
          onSubmitted: _addPackage,
        ),
      ],
    );
  }
}

class _PackageRow extends StatelessWidget {
  const _PackageRow({
    super.key,
    required this.package,
    required this.inTransit,
    required this.now,
    required this.onOpen,
    required this.onEta,
    required this.onRemove,
  });

  final Package package;
  final bool inTransit;
  final DateTime now;
  final VoidCallback? onOpen;
  final VoidCallback onEta;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eta = package.eta;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Icon(
            inTransit ? Icons.local_shipping : Icons.inventory_2_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${package.carrier.label} ${package.tracking}'),
                if (package.status != null)
                  Text(package.status!.label, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          TextButton(
            onPressed: onEta,
            child: Text(
              eta == null ? 'Add ETA' : dayLabel(eta, now, short: true),
            ),
          ),
          if (onOpen != null)
            IconButton(
              tooltip: 'Track ${package.tracking}',
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new, size: 18),
            ),
          IconButton(
            tooltip: 'Remove ${package.tracking}',
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}
