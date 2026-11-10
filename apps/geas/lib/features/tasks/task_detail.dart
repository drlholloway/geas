import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';

import '../../app/theme.dart';
import '../../state/store.dart';
import 'due_label.dart';

/// Shows the task with [id] in a sheet where every field can be edited.
/// Changes save as they're made.
Future<void> showTaskDetail(BuildContext context, String id) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => _TaskDetail(id: id),
    );

class _TaskDetail extends ConsumerStatefulWidget {
  const _TaskDetail({required this.id});

  final String id;

  @override
  ConsumerState<_TaskDetail> createState() => _TaskDetailState();
}

class _TaskDetailState extends ConsumerState<_TaskDetail> {
  late final TextEditingController _title;
  final _newItem = TextEditingController();
  final _newItemFocus = FocusNode();

  /// The whole body as Markdown, while editing it; null otherwise.
  TextEditingController? _body;

  TaskStoreNotifier get _store => ref.read(taskStoreProvider.notifier);

  void _edit(Task Function(Task task) change) => _store.edit(widget.id, change);

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: _current()?.title ?? '');
  }

  Task? _current() {
    for (final task in ref.read(taskStoreProvider).tasks) {
      if (task.id == widget.id) return task;
    }
    return null;
  }

  @override
  void dispose() {
    _title.dispose();
    _newItem.dispose();
    _newItemFocus.dispose();
    _body?.dispose();
    super.dispose();
  }

  void _addItem(String text) {
    if (text.trim().isEmpty) return;
    _edit((t) => t.copyWith(body: addChecklistItem(t.body, text)));
    _newItem.clear();
    _newItemFocus.requestFocus();
  }

  void _toggleBodyEditor(Task task) => setState(() {
    if (_body == null) {
      _body = TextEditingController(text: task.body);
    } else {
      _body!.dispose();
      _body = null;
    }
  });

  Future<void> _delete(Task task) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this task?'),
        content: Text('"${task.title}" goes from every device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if ((yes ?? false) && mounted) {
      Navigator.pop(context);
      _store.delete(task.id);
    }
  }

  Future<void> _addTag(Task task) async {
    final known = allTags(ref.read(taskStoreProvider).tasks)
        .where((t) => !task.tags.any((x) => x.toLowerCase() == t.toLowerCase()))
        .toList();
    final tag = await showDialog<String>(
      context: context,
      builder: (context) => _TagDialog(known: known),
    );
    if (tag == null || tag.isEmpty) return;
    _edit(
      (t) => t.tags.any((x) => x.toLowerCase() == tag.toLowerCase())
          ? t
          : t.copyWith(tags: [...t.tags, tag]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(taskStoreProvider);
    final now = ref.watch(clockProvider)();
    Task? found;
    for (final t in store.tasks) {
      if (t.id == widget.id) found = t;
    }
    // Deleted, here or by a sync.
    if (found == null) return const SizedBox(height: 120);
    final task = found;

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
    final priorityTint = priorityColor(task.priority, theme.colorScheme);
    final body = _body;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Checkbox(
                  value: task.isCompleted,
                  side: BorderSide(color: priorityTint, width: 2),
                  onChanged: (v) => _store.setDone(task, done: v ?? false),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _title,
                    style: theme.textTheme.titleLarge,
                    maxLines: null,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Title',
                    ),
                    onChanged: (text) {
                      if (text.trim().isEmpty) return;
                      _edit((t) => t.copyWith(title: text.trim()));
                    },
                  ),
                ),
                PopupMenuButton<void>(
                  tooltip: 'More',
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      onTap: () => _delete(task),
                      child: const ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ListChip(
                  task: task,
                  lists: store.lists,
                  current: list,
                  onSelected: (id) => _edit((t) => t.copyWith(list: id)),
                ),
                _DueChip(
                  due: task.due,
                  now: now,
                  onChanged: (due) => _edit((t) => t.copyWith(due: due)),
                ),
                _PriorityChip(
                  priority: task.priority,
                  onSelected: (p) => _edit((t) => t.copyWith(priority: p)),
                ),
                for (final tag in task.tags)
                  InputChip(
                    label: Text('#$tag'),
                    deleteButtonTooltipMessage: 'Remove #$tag',
                    onDeleted: () => _edit(
                      (t) => t.copyWith(
                        tags: [
                          for (final x in t.tags)
                            if (x != tag) x,
                        ],
                      ),
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.tag, size: 16),
                  label: const Text('Add tag'),
                  onPressed: () => _addTag(task),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (body != null) ...[
              TextField(
                controller: body,
                minLines: 6,
                maxLines: null,
                style: theme.textTheme.bodyMedium!.copyWith(
                  fontFamily: 'monospace',
                ),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  helperText:
                      'Markdown. Lines like "- [ ] item" are the '
                      'checklist.',
                ),
                onChanged: (text) => _edit((t) => t.copyWith(body: text)),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _toggleBodyEditor(task),
                  child: const Text('Done'),
                ),
              ),
            ] else ...[
              for (final item in checklist)
                Padding(
                  padding: EdgeInsets.only(left: item.indent * 8.0),
                  child: Row(
                    children: [
                      Checkbox(
                        value: item.done,
                        onChanged: (v) => _store.setChecklistItem(
                          task,
                          item.line,
                          done: v ?? false,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          item.text,
                          style: item.done
                              ? TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  decoration: TextDecoration.lineThrough,
                                )
                              : null,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove item',
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _edit(
                          (t) => t.copyWith(
                            body: removeChecklistLine(t.body, item.line),
                          ),
                        ),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: TextField(
                  controller: _newItem,
                  focusNode: _newItemFocus,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    icon: Icon(Icons.add, size: 20),
                    hintText: 'Add an item',
                  ),
                  onSubmitted: _addItem,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _toggleBodyEditor(task),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          notes.isEmpty ? 'Add notes' : notes,
                          style: notes.isEmpty
                              ? theme.textTheme.bodyMedium!.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                )
                              : theme.textTheme.bodyMedium,
                        ),
                      ),
                      Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ListChip extends StatelessWidget {
  const _ListChip({
    required this.task,
    required this.lists,
    required this.current,
    required this.onSelected,
  });

  final Task task;
  final List<TaskList> lists;
  final TaskList? current;
  final void Function(String id) onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'List',
    initialValue: task.list,
    onSelected: onSelected,
    itemBuilder: (context) => [
      for (final list in lists)
        PopupMenuItem(
          value: list.id,
          child: Row(
            children: [
              Icon(Icons.circle, size: 10, color: parseHexColor(list.color)),
              const SizedBox(width: 12),
              Text(list.name),
            ],
          ),
        ),
    ],
    child: Chip(
      avatar: Icon(
        Icons.circle,
        size: 10,
        color: parseHexColor(current?.color),
      ),
      label: Text(current?.name ?? task.list),
    ),
  );
}

enum _DueAction { today, tomorrow, pick, time, removeTime, clear }

class _DueChip extends StatelessWidget {
  const _DueChip({
    required this.due,
    required this.now,
    required this.onChanged,
  });

  final Due? due;
  final DateTime now;
  final void Function(Due? due) onChanged;

  /// [day], keeping the time of day if [due] has one.
  Due _on(LocalDate day) {
    final time = _time;
    return time == null ? Due.date(day) : _at(day, time);
  }

  TimeOfDay? get _time {
    final instant = due?.instant?.toLocal();
    return instant == null ? null : TimeOfDay.fromDateTime(instant);
  }

  /// A time in this device's zone, like `geas add -d "fri 5pm"`.
  static Due _at(LocalDate day, TimeOfDay time) => Due.at(
    day,
    time.hour,
    time.minute,
    offset: DateTime(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    ).timeZoneOffset,
  );

  Future<void> _choose(BuildContext context, _DueAction action) async {
    final today = LocalDate.of(now);
    final day = due?.localDate ?? today;
    switch (action) {
      case _DueAction.today:
        onChanged(_on(today));
      case _DueAction.tomorrow:
        onChanged(_on(today.addDays(1)));
      case _DueAction.pick:
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime(day.year, day.month, day.day),
          firstDate: DateTime(now.year - 5),
          lastDate: DateTime(now.year + 10, 12, 31),
        );
        if (picked != null) onChanged(_on(LocalDate.of(picked)));
      case _DueAction.time:
        final picked = await showTimePicker(
          context: context,
          initialTime: _time ?? const TimeOfDay(hour: 9, minute: 0),
        );
        if (picked != null) onChanged(_at(day, picked));
      case _DueAction.removeTime:
        onChanged(Due.date(day));
      case _DueAction.clear:
        onChanged(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final due = this.due;
    return PopupMenuButton<_DueAction>(
      tooltip: 'Due date',
      onSelected: (action) => _choose(context, action),
      itemBuilder: (context) => [
        const PopupMenuItem(value: _DueAction.today, child: Text('Today')),
        const PopupMenuItem(
          value: _DueAction.tomorrow,
          child: Text('Tomorrow'),
        ),
        const PopupMenuItem(
          value: _DueAction.pick,
          child: Text('Pick a date…'),
        ),
        PopupMenuItem(
          value: _DueAction.time,
          child: Text(
            due?.hasTime ?? false ? 'Change the time…' : 'Add a time…',
          ),
        ),
        if (due?.hasTime ?? false)
          const PopupMenuItem(
            value: _DueAction.removeTime,
            child: Text('Remove the time'),
          ),
        if (due != null)
          const PopupMenuItem(value: _DueAction.clear, child: Text('No date')),
      ],
      child: Chip(
        avatar: const Icon(Icons.event, size: 16),
        label: Text(due == null ? 'Add date' : dueLabel(due, now)),
      ),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({required this.priority, required this.onSelected});

  final Priority priority;
  final void Function(Priority priority) onSelected;

  static String _name(Priority p) => switch (p) {
    Priority.high => 'High',
    Priority.medium => 'Medium',
    Priority.low => 'Low',
    Priority.none => 'None',
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopupMenuButton<Priority>(
      tooltip: 'Priority',
      initialValue: priority,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final p in Priority.values.reversed)
          PopupMenuItem(
            value: p,
            child: Row(
              children: [
                Icon(Icons.flag, size: 18, color: priorityColor(p, colors)),
                const SizedBox(width: 12),
                Text(_name(p)),
              ],
            ),
          ),
      ],
      child: Chip(
        avatar: Icon(
          priority == Priority.none ? Icons.outlined_flag : Icons.flag,
          size: 16,
          color: priorityColor(priority, colors),
        ),
        label: Text(
          priority == Priority.none
              ? 'Priority'
              : '${_name(priority)} priority',
        ),
      ),
    );
  }
}

class _TagDialog extends StatefulWidget {
  const _TagDialog({required this.known});

  /// Tags on other tasks, to pick from.
  final List<String> known;

  @override
  State<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<_TagDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// One word, without the `#`.
  static String _clean(String text) => text
      .trim()
      .replaceFirst(RegExp(r'^#+'), '')
      .replaceAll(RegExp(r'\s+'), '-');

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add a tag'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _text,
          autofocus: true,
          autocorrect: false,
          decoration: const InputDecoration(prefixText: '#', hintText: 'tag'),
          onSubmitted: (text) => Navigator.pop(context, _clean(text)),
        ),
        if (widget.known.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in widget.known)
                ActionChip(
                  label: Text('#$tag'),
                  onPressed: () => Navigator.pop(context, tag),
                ),
            ],
          ),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _clean(_text.text)),
        child: const Text('Add'),
      ),
    ],
  );
}
