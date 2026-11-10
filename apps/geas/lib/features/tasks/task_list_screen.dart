import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final sections = view.sections(store, now);
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
          for (final section in sections) ...[
            _SectionHeader(
              title: section.title,
              count: section.tasks.length,
              color: section.alert ? theme.colorScheme.error : null,
            ),
            for (final task in section.tasks)
              TaskTile(key: ValueKey(task.id), task: task, showList: showList),
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
    final title = text.trim();
    if (title.isEmpty) return;
    final view = widget.view;
    ref
        .read(taskStoreProvider.notifier)
        .add(
          title,
          list: view.newTaskList,
          tags: view.newTaskTags,
          due: view.newTaskDue(ref.read(clockProvider)()),
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
