import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';

import '../../app/theme.dart';
import '../../state/store.dart';
import 'due_label.dart';

/// Shows the task with [id] in a sheet. Read-only for now apart from the
/// done box and the checklist; full editing is a later step.
Future<void> showTaskDetail(BuildContext context, String id) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => _TaskDetail(id: id),
    );

class _TaskDetail extends ConsumerWidget {
  const _TaskDetail({required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(taskStoreProvider);
    final now = ref.watch(clockProvider)();
    final task = store.tasks.firstWhere((t) => t.id == id);
    final notifier = ref.read(taskStoreProvider.notifier);
    final theme = Theme.of(context);
    final checklist = task.checklist;
    final checklistLines = {for (final item in checklist) item.line};
    final notes = task.body
        .split('\n')
        .indexed
        .where((e) => !checklistLines.contains(e.$1))
        .map((e) => e.$2)
        .join('\n')
        .trim();
    final list = store.listById(task.list);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Checkbox(
                  value: task.isCompleted,
                  side: BorderSide(
                    color: priorityColor(task.priority, theme.colorScheme),
                    width: 2,
                  ),
                  onChanged: (v) => notifier.setDone(task, done: v ?? false),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(task.title, style: theme.textTheme.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: Icon(
                    Icons.circle,
                    size: 10,
                    color: parseHexColor(list?.color),
                  ),
                  label: Text(list?.name ?? task.list),
                ),
                if (task.due != null)
                  Chip(
                    avatar: const Icon(Icons.event, size: 16),
                    label: Text(dueLabel(task.due!, now)),
                  ),
                if (task.priority != Priority.none)
                  Chip(
                    avatar: Icon(
                      Icons.flag,
                      size: 16,
                      color: priorityColor(task.priority, theme.colorScheme),
                    ),
                    label: Text('${task.priority.name} priority'),
                  ),
                for (final tag in task.tags) Chip(label: Text('#$tag')),
              ],
            ),
            if (checklist.isNotEmpty) ...[
              const SizedBox(height: 16),
              for (final item in checklist)
                CheckboxListTile(
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.only(left: item.indent * 8.0),
                  value: item.done,
                  title: Text(item.text),
                  onChanged: (v) => notifier.setChecklistItem(
                    task,
                    item.line,
                    done: v ?? false,
                  ),
                ),
            ],
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(notes, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}
