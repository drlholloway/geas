import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../state/store.dart';
import '../folders/folder_actions.dart';
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

    Widget page(String path, String title, IconData icon, {int count = 0}) =>
        ListTile(
          dense: true,
          selected: location == path || location.startsWith('$path/'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          leading: Icon(icon, size: 20),
          title: Text(title),
          trailing: count == 0 ? null : Text('$count'),
          onTap: () {
            final scaffold = Scaffold.maybeOf(context);
            if (scaffold != null && scaffold.isDrawerOpen) {
              scaffold.closeDrawer();
            }
            context.go(path);
          },
        );
    final openOrders = store.tasks
        .where(
          (t) => !t.isCompleted && t.order != null && !t.order!.status.isDone,
        )
        .length;

    final healthDue = store.trackers
        .where((t) => TrackerStats.of(t, now).nextDue?.isBefore(now) ?? false)
        .length;

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

    // Something filed in a folder that's gone counts as in none.
    String? folderOf(String? id) => store.folderById(id)?.id;
    final lists = store.lists.where((l) => l.id != inboxId).toList();
    final tags = allTags(store.tasks);
    final collapsed = ref.watch(collapsedFoldersProvider);

    Widget listItem(TaskList list) => item(
      TaskView(ViewKind.list, list.id),
      Icons.circle,
      iconColor: parseHexColor(list.color),
    );
    Widget filterItem(SavedFilter filter) => page(
      '/filter/${filter.id}',
      filter.name,
      Icons.filter_list,
      count: TaskQuery.parse(
        filter.query,
        lists: store.lists,
      ).search(store.tasks, now).length,
    );
    void closeDrawer() {
      final scaffold = Scaffold.maybeOf(context);
      if (scaffold != null && scaffold.isDrawerOpen) scaffold.closeDrawer();
    }

    /// A folder's heading, then what's in it unless it's collapsed.
    List<Widget> folderSection(Folder folder) {
      final open = !collapsed.contains(folder.id);
      final inLists = lists.where((l) => l.folder == folder.id);
      final inFilters = store.filters.where((f) => f.folder == folder.id);
      final inHealth = store.trackers
          .where((t) => t.folder == folder.id)
          .length;
      return [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () =>
                ref.read(collapsedFoldersProvider.notifier).toggle(folder.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 0, 0),
              child: Row(
                children: [
                  Icon(
                    open ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    open ? Icons.folder_open_outlined : Icons.folder_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      folder.name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  FolderMenu(folder: folder),
                ],
              ),
            ),
          ),
        ),
        if (open) ...[
          for (final list in inLists) listItem(list),
          for (final filter in inFilters) filterItem(filter),
          if (inHealth > 0)
            ListTile(
              dense: true,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              leading: const Icon(Icons.medication_outlined, size: 20),
              title: Text('$inHealth in Health'),
              onTap: () {
                closeDrawer();
                context.go('/health');
              },
            ),
          if (inLists.isEmpty && inFilters.isEmpty && inHealth == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(52, 4, 16, 4),
              child: Text(
                'Empty. Move a list, filter or tracker here from its menu.',
                style: theme.textTheme.bodySmall!.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ];
    }

    final looseFilters = store.filters
        .where((f) => folderOf(f.folder) == null)
        .toList();

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
                page('/matrix', 'Matrix', Icons.grid_view),
                page(
                  '/orders',
                  'Orders',
                  Icons.local_shipping_outlined,
                  count: openOrders,
                ),
                page(
                  '/health',
                  'Health',
                  Icons.medication_outlined,
                  count: healthDue,
                ),
                page('/search', 'Search', Icons.search),
                for (final folder in store.folders) ...folderSection(folder),
                if (looseFilters.isNotEmpty) heading('Filters'),
                for (final filter in looseFilters) filterItem(filter),
                heading(
                  'Lists',
                  action: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Add folder',
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          closeDrawer();
                          addFolder(context, ref);
                        },
                        icon: const Icon(Icons.create_new_folder_outlined),
                      ),
                      IconButton(
                        tooltip: 'Add list',
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          closeDrawer();
                          addList(context, ref);
                        },
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
                for (final list in lists)
                  if (folderOf(list.folder) == null) listItem(list),
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
