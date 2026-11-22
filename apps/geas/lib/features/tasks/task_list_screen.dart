import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';

import '../../state/store.dart';
import '../lists/list_actions.dart';
import '../shell/sidebar.dart';
import 'task_tile.dart';
import 'task_view.dart';

/// The tasks in one [TaskView], grouped into sections, with a quick-add
/// field on top and a collapsed Completed section at the bottom.
class TaskListScreen extends ConsumerWidget {
  const TaskListScreen({super.key, required this.view});

  final TaskView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(taskStoreProvider);
    final now = ref.watch(clockProvider)();
    // A list sorted by hand shows its open tasks in that order, not in
    // sections by due date.
    final manual =
        view.kind == ViewKind.list &&
            (store.listById(view.arg)?.manual ?? false)
        ? manualOrder(
            store.tasks.where((t) => t.list == view.arg && !t.isCompleted),
          )
        : null;
    final sections = manual == null
        ? view.sections(store, now)
        : [if (manual.isNotEmpty) TaskSection('', manual)];
    final completed = view.completed(store);
    final narrow = MediaQuery.sizeOf(context).width < sidebarBreakpoint;
    final showList = view.kind != ViewKind.list;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(view.title(store)),
        actions: [ViewMenu(view: view)],
      ),
      drawer: narrow ? const Drawer(child: Sidebar()) : null,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: _QuickAdd(view: view, title: view.title(store)),
          ),
          if (sections.isEmpty && completed.isEmpty)
            Padding(
              padding: const EdgeInsets.all(48),
              child: Center(
                child: Text(
                  'Nothing here.',
                  style: theme.textTheme.bodyLarge!.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          if (manual != null)
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              // Each row has its own handle, so a tap or scroll that starts
              // on a row never picks it up.
              buildDefaultDragHandles: false,
              proxyDecorator: (child, _, _) => Material(child: child),
              onReorderItem: (from, to) => ref
                  .read(taskStoreProvider.notifier)
                  .moveTask(view.arg, manual[from].id, to),
              children: [
                for (final (index, task) in manual.indexed)
                  Row(
                    key: ValueKey(task.id),
                    children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: Tooltip(
                          message: 'Drag to reorder',
                          child: MouseRegion(
                            cursor: SystemMouseCursors.grab,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
                              child: Icon(
                                Icons.drag_indicator,
                                size: 20,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(child: TaskTile(task: task, showList: false)),
                    ],
                  ),
              ],
            )
          else
            for (final section in sections) ...[
              _SectionHeader(
                title: section.title,
                count: section.tasks.length,
                color: section.alert ? theme.colorScheme.error : null,
              ),
              for (final task in section.tasks)
                TaskTile(
                  key: ValueKey(task.id),
                  task: task,
                  showList: showList,
                ),
            ],
          if (completed.isNotEmpty)
            Theme(
              // No divider lines around the expansion tile.
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: Text(
                  'Completed (${completed.length})',
                  style: theme.textTheme.titleSmall,
                ),
                children: [
                  for (final task in completed)
                    TaskTile(
                      key: ValueKey(task.id),
                      task: task,
                      showList: showList,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count, this.color});

  final String title;
  final int count;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall!
        .copyWith(color: color ?? Theme.of(context).colorScheme.primary);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text('$title  $count', style: style),
    );
  }
}

class _QuickAdd extends ConsumerStatefulWidget {
  const _QuickAdd({required this.view, required this.title});

  final TaskView view;
  final String title;

  @override
  ConsumerState<_QuickAdd> createState() => _QuickAddState();
}

class _QuickAddState extends ConsumerState<_QuickAdd> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String text) {
    if (text.trim().isEmpty) return;
    final view = widget.view;
    final now = ref.read(clockProvider)();
    // `#tag`, `^list`, `!high` and a date at the end, over what the view
    // gives a new task.
    final typed = parseQuickAdd(
      text,
      now: now,
      lists: ref.read(taskStoreProvider).lists,
    );
    ref
        .read(taskStoreProvider.notifier)
        .add(
          typed.title,
          list: typed.list ?? view.newTaskList,
          tags: [
            ...view.newTaskTags,
            for (final tag in typed.tags)
              if (!view.newTaskTags.contains(tag)) tag,
          ],
          due: typed.due ?? view.newTaskDue(now),
          priority: typed.priority ?? Priority.none,
        );
    _controller.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    focusNode: _focus,
    textInputAction: TextInputAction.done,
    decoration: InputDecoration(
      hintText: 'Add a task to ${widget.title}',
      helperText: '#tag  ^list  !high  and a date at the end, like fri 5pm',
      prefixIcon: const Icon(Icons.add),
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      isDense: true,
    ),
    onSubmitted: _submit,
  );
}
