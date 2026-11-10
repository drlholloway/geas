import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';

import '../../state/environment.dart';
import '../../state/store.dart';
import '../shell/sidebar.dart';
import '../tasks/due_label.dart';
import '../tasks/task_detail.dart';

/// Orders by status, with vendor, number, carrier, ETA and buttons for the
/// tracking pages. Delivered and returned ones are collapsed.
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(taskStoreProvider);
    final now = ref.watch(clockProvider)();
    final narrow = MediaQuery.sizeOf(context).width < sidebarBreakpoint;
    final theme = Theme.of(context);
    final groups = ordersByStatus(store.tasks);
    final empty = groups.values.every((g) => g.isEmpty);

    Widget section(OrderStatus status) {
      final tasks = groups[status]!;
      final tiles = [
        for (final task in tasks)
          _OrderTile(key: ValueKey(task.id), task: task, now: now),
      ];
      final title = '${status.label}  ${tasks.length}';
      if (status.isDone) {
        return Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: Text(title, style: theme.textTheme.titleSmall),
            children: tiles,
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              title,
              style: theme.textTheme.titleSmall!.copyWith(
                color: status == OrderStatus.problem
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
            ),
          ),
          ...tiles,
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      drawer: narrow ? const Drawer(child: Sidebar()) : null,
      body: empty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No orders. Open a task and choose "Track an order".',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge!.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                for (final status in OrderStatus.values)
                  if (groups[status]!.isNotEmpty) section(status),
              ],
            ),
    );
  }
}

class _OrderTile extends ConsumerWidget {
  const _OrderTile({super.key, required this.task, required this.now});

  final Task task;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final order = task.order!;
    final env = ref.read(environmentProvider);
    final muted = theme.textTheme.bodySmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final vendor = [
      ?order.vendor,
      if (order.number != null) '#${order.number}',
    ].join('  ');

    return InkWell(
      onTap: () => showTaskDetail(context, task.id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              task.title,
              style: task.isCompleted
                  ? TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      decoration: TextDecoration.lineThrough,
                    )
                  : theme.textTheme.bodyLarge,
            ),
            if (vendor.isNotEmpty) Text(vendor, style: muted),
            for (final p in order.packages)
              Row(
                children: [
                  Icon(
                    p.inTransit(order.status)
                        ? Icons.local_shipping
                        : Icons.inventory_2_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      [
                        '${p.carrier.label} ${p.tracking}',
                        if (p.eta != null)
                          'ETA ${dayLabel(p.eta!, now, short: true)}',
                        if (p.status != null) p.status!.label,
                      ].join('  ·  '),
                      style: muted,
                    ),
                  ),
                  if (p.trackingUrl != null)
                    IconButton(
                      tooltip: 'Track ${p.tracking}',
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      onPressed: () => env.openUrl(p.trackingUrl!),
                      icon: const Icon(Icons.open_in_new),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
