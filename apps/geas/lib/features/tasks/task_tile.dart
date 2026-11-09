import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';

import '../../app/theme.dart';
import '../../state/store.dart';
import 'due_label.dart';
import 'task_detail.dart';

/// One task: checkbox in its priority color, title, then due date, list,
/// tags and checklist progress.
class TaskTile extends ConsumerWidget {
  const TaskTile({super.key, required this.task, this.showList = true});

  final Task task;

  /// Off when the screen is already showing that list.
  final bool showList;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final now = ref.watch(clockProvider)();
    final store = ref.watch(taskStoreProvider);
    final done = task.isCompleted;
    final checklist = task.checklist;

    final details = <Widget>[];
    final due = task.due;
    if (due != null) {
      final overdue = !done && dueBucket(task, now) == DueBucket.overdue;
      details.add(
        _Detail(
          icon: Icons.event,
          text: dueLabel(due, now),
          color: overdue ? colors.error : null,
        ),
      );
    }
    if (showList && task.list != inboxId) {
      final list = store.listById(task.list);
      details.add(
        _Detail(
          icon: Icons.circle,
          iconColor: parseHexColor(list?.color),
          text: list?.name ?? task.list,
        ),
      );
    }
    if (checklist.isNotEmpty) {
      final ticked = checklist.where((i) => i.done).length;
      details.add(
        _Detail(icon: Icons.checklist, text: '$ticked/${checklist.length}'),
      );
    }
    for (final tag in task.tags) {
      details.add(_Detail(text: '#$tag'));
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Checkbox(
        value: done,
        side: BorderSide(color: priorityColor(task.priority, colors), width: 2),
        onChanged: (value) => ref
            .read(taskStoreProvider.notifier)
            .setDone(task, done: value ?? false),
      ),
      title: Text(
        task.title,
        style: done
            ? TextStyle(
                color: colors.onSurfaceVariant,
                decoration: TextDecoration.lineThrough,
              )
            : null,
      ),
      subtitle: details.isEmpty
          ? null
          : Wrap(spacing: 12, runSpacing: 2, children: details),
      onTap: () => showTaskDetail(context, task.id),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({this.icon, this.iconColor, required this.text, this.color});

  final IconData? icon;
  final Color? iconColor;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall!.copyWith(
      color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: icon == Icons.circle ? 8 : 14,
            color: iconColor ?? style.color,
          ),
          const SizedBox(width: 4),
        ],
        Text(text, style: style),
      ],
    );
  }
}
