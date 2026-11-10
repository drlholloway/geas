import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../state/store.dart';
import '../lists/list_actions.dart';
import '../tasks/task_view.dart';
import 'sync_status.dart';

/// Below this width the sidebar moves into a drawer.
const sidebarBreakpoint = 720.0;

/// Inbox, Today and Next 7 days, then lists and tags, each with its count of
/// open tasks.
class Sidebar extends ConsumerWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(taskStoreProvider);
    final now = ref.watch(clockProvider)();
    final location = GoRouterState.of(context).uri.path;
    final theme = Theme.of(context);

    Widget item(TaskView view, IconData icon, {Color? iconColor}) {
      final count = view.openCount(store, now);
      return ListTile(
        dense: true,
        selected: location == view.location,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(icon, size: 20, color: iconColor),
        title: Text(view.title(store)),
        trailing: count == 0 ? null : Text('$count'),
        onTap: () {
          final scaffold = Scaffold.maybeOf(context);
          if (scaffold != null && scaffold.isDrawerOpen) scaffold.closeDrawer();
          context.go(view.location);
        },
      );
    }

    Widget heading(String text, {Widget? action}) => Padding(
      padding: EdgeInsets.fromLTRB(16, action == null ? 20 : 8, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.labelMedium!.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );

    final lists = store.lists.where((l) => l.id != inboxId);
    final tags = allTags(store.tasks);

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Text(
                    'Geas',
                    style: theme.textTheme.headlineSmall!.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                item(const TaskView(ViewKind.list, inboxId), Icons.inbox),
                item(const TaskView(ViewKind.today), Icons.today),
                item(const TaskView(ViewKind.week), Icons.date_range),
                ListTile(
                  dense: true,
                  selected: location == '/matrix',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  leading: const Icon(Icons.grid_view, size: 20),
                  title: const Text('Matrix'),
                  onTap: () {
                    final scaffold = Scaffold.maybeOf(context);
                    if (scaffold != null && scaffold.isDrawerOpen) {
                      scaffold.closeDrawer();
                    }
                    context.go('/matrix');
                  },
                ),
                heading(
                  'Lists',
                  action: IconButton(
                    tooltip: 'Add list',
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      final scaffold = Scaffold.maybeOf(context);
                      if (scaffold != null && scaffold.isDrawerOpen) {
                        scaffold.closeDrawer();
                      }
                      addList(context, ref);
                    },
                    icon: const Icon(Icons.add),
                  ),
                ),
                for (final list in lists)
                  item(
                    TaskView(ViewKind.list, list.id),
                    Icons.circle,
                    iconColor: parseHexColor(list.color),
                  ),
                if (tags.isNotEmpty) heading('Tags'),
                for (final tag in tags)
                  item(TaskView(ViewKind.tag, tag), Icons.tag),
              ],
            ),
          ),
          const SyncStatusBar(),
        ],
      ),
    );
  }
}
