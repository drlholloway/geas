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
      floatingActionButton: empty
          ? null
          : FloatingActionButton(
              tooltip: 'Add an order',
              onPressed: () => addOrder(context, ref),
              child: const Icon(Icons.add),
            ),
      body: empty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No orders yet.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge!.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => addOrder(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('Add an order'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              // Room for the add button over the last row.
              padding: const EdgeInsets.only(bottom: 88),
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

/// Asks what's coming, from whom, and optionally a tracking number, then
/// adds a task for the order to the inbox and opens it.
Future<void> addOrder(BuildContext context, WidgetRef ref) async {
  final created = await showDialog<({String title, Order order})>(
    context: context,
    builder: (context) => const _NewOrderDialog(),
  );
  if (created == null || !context.mounted) return;
  final task = ref
      .read(taskStoreProvider.notifier)
      .add(created.title, order: created.order);
  await showTaskDetail(context, task.id);
}

class _NewOrderDialog extends StatefulWidget {
  const _NewOrderDialog();

  @override
  State<_NewOrderDialog> createState() => _NewOrderDialogState();
}

class _NewOrderDialogState extends State<_NewOrderDialog> {
  final _title = TextEditingController();
  final _vendor = TextEditingController();
  final _number = TextEditingController();
  final _tracking = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _vendor]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _vendor, _number, _tracking]) {
      c.dispose();
    }
    super.dispose();
  }

  static String? _orNull(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  /// What's typed, or "Order from" and the vendor if only that is.
  String? get _taskTitle {
    final title = _orNull(_title);
    if (title != null) return title;
    final vendor = _orNull(_vendor);
    return vendor == null ? null : 'Order from $vendor';
  }

  void _save() {
    final title = _taskTitle;
    if (title == null) return;
    var order = Order(vendor: _orNull(_vendor), number: _orNull(_number));
    final tracking = _orNull(_tracking);
    if (tracking != null) order = order.withPackage(Package.track(tracking));
    Navigator.pop(context, (title: title, order: order));
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration field(String label, {String? hint}) =>
        InputDecoration(labelText: label, hintText: hint);
    return AlertDialog(
      title: const Text('New order'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: field('What\'s coming', hint: 'Order 1N914s'),
            ),
            TextField(
              controller: _vendor,
              textInputAction: TextInputAction.next,
              decoration: field('Vendor'),
            ),
            TextField(
              controller: _number,
              textInputAction: TextInputAction.next,
              decoration: field('Order number'),
            ),
            TextField(
              controller: _tracking,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              decoration: field(
                'Tracking number',
                hint: 'Optional; add packages later too',
              ),
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _taskTitle == null ? null : _save,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
