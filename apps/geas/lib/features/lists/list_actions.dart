import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../state/store.dart';
import '../tasks/task_view.dart';

/// Colors to pick from for a list.
const listColors = [
  '#D64545', '#E07A2F', '#E0A030', '#4CAF50', '#2E8B8B', //
  '#3C8DBC', '#7E57C2', '#C2185B', '#8D6E63',
];

/// Asks for a new list's name and color, then adds it and shows it.
Future<void> addList(BuildContext context, WidgetRef ref) async {
  final store = ref.read(taskStoreProvider.notifier);
  final created = await showDialog<TaskList>(
    context: context,
    builder: (context) => _ListDialog(
      lists: ref.read(taskStoreProvider).lists,
      onSave: (name, color) =>
          newList(name, ref.read(taskStoreProvider).lists, color: color),
    ),
  );
  if (created == null) return;
  store.saveList(created);
  if (context.mounted) {
    context.go(TaskView(ViewKind.list, created.id).location);
  }
}

/// The menu on a list's or tag's screen: edit or delete the list, or
/// rename or remove the tag. Nothing for Today and Next 7 days.
class ViewMenu extends ConsumerWidget {
  const ViewMenu({super.key, required this.view});

  final TaskView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (view.kind) {
    ViewKind.list => _listMenu(context, ref),
    ViewKind.tag => _tagMenu(context, ref),
    ViewKind.today || ViewKind.week => const SizedBox.shrink(),
  };

  Widget _listMenu(BuildContext context, WidgetRef ref) {
    final store = ref.watch(taskStoreProvider);
    final list = store.listById(view.arg);
    if (list == null) return const SizedBox.shrink();
    return PopupMenuButton<void>(
      tooltip: 'List options',
      itemBuilder: (_) => [
        PopupMenuItem(
          onTap: () => _editList(context, ref, list),
          child: const ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Edit list'),
          ),
        ),
        if (list.id != inboxId)
          PopupMenuItem(
            onTap: () => _deleteList(context, ref, list),
            child: const ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('Delete list'),
            ),
          ),
      ],
    );
  }

  Future<void> _editList(
    BuildContext context,
    WidgetRef ref,
    TaskList list,
  ) async {
    final edited = await showDialog<TaskList>(
      context: context,
      builder: (context) => _ListDialog(
        list: list,
        lists: ref.read(taskStoreProvider).lists,
        onSave: (name, color) {
          final others = ref.read(taskStoreProvider).lists;
          if (others.any(
            (l) =>
                l.id != list.id && l.name.toLowerCase() == name.toLowerCase(),
          )) {
            throw FormatException('There is already a list called "$name".');
          }
          return list.copyWith(name: name, color: color);
        },
      ),
    );
    if (edited != null && edited != list) {
      ref.read(taskStoreProvider.notifier).saveList(edited);
    }
  }

  Future<void> _deleteList(
    BuildContext context,
    WidgetRef ref,
    TaskList list,
  ) async {
    final count = ref
        .read(taskStoreProvider)
        .tasks
        .where((t) => t.list == list.id)
        .length;
    final yes = await _confirm(
      context,
      title: 'Delete ${list.name}?',
      body: count == 0
          ? 'The list is empty.'
          : 'Its ${_tasks(count)} move to the Inbox.',
      action: 'Delete',
    );
    if (!yes || !context.mounted) return;
    context.go(const TaskView(ViewKind.list, inboxId).location);
    ref.read(taskStoreProvider.notifier).deleteList(list.id);
  }

  Widget _tagMenu(BuildContext context, WidgetRef ref) => PopupMenuButton<void>(
    tooltip: 'Tag options',
    itemBuilder: (_) => [
      PopupMenuItem(
        onTap: () => _renameTag(context, ref),
        child: const ListTile(
          leading: Icon(Icons.edit_outlined),
          title: Text('Rename tag'),
        ),
      ),
      PopupMenuItem(
        onTap: () => _removeTag(context, ref),
        child: const ListTile(
          leading: Icon(Icons.delete_outline),
          title: Text('Remove tag'),
        ),
      ),
    ],
  );

  int _tagged(WidgetRef ref) {
    final lower = view.arg.toLowerCase();
    return ref
        .read(taskStoreProvider)
        .tasks
        .where((t) => t.tags.any((tag) => tag.toLowerCase() == lower))
        .length;
  }

  Future<void> _renameTag(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _TagNameDialog(tag: view.arg),
    );
    if (name == null || name.isEmpty || name == view.arg || !context.mounted) {
      return;
    }
    context.go(TaskView(ViewKind.tag, name).location);
    ref.read(taskStoreProvider.notifier).renameTag(view.arg, name);
  }

  Future<void> _removeTag(BuildContext context, WidgetRef ref) async {
    final yes = await _confirm(
      context,
      title: 'Remove #${view.arg}?',
      body: 'It comes off ${_tasks(_tagged(ref))}. The tasks stay.',
      action: 'Remove',
    );
    if (!yes || !context.mounted) return;
    context.go(const TaskView(ViewKind.list, inboxId).location);
    ref.read(taskStoreProvider.notifier).renameTag(view.arg, null);
  }
}

String _tasks(int n) => n == 1 ? '1 task' : '$n tasks';

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

/// A list's name and color. [onSave] builds the list, throwing
/// [FormatException] to show a problem instead.
class _ListDialog extends StatefulWidget {
  const _ListDialog({this.list, required this.lists, required this.onSave});

  /// The list being edited; null for a new one.
  final TaskList? list;
  final List<TaskList> lists;
  final TaskList Function(String name, String? color) onSave;

  @override
  State<_ListDialog> createState() => _ListDialogState();
}

class _ListDialogState extends State<_ListDialog> {
  late final _name = TextEditingController(text: widget.list?.name ?? '');
  late String? _color = widget.list == null
      ? listColors[widget.lists.length % listColors.length]
      : widget.list!.color;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    try {
      Navigator.pop(context, widget.onSave(name, _color));
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget swatch(String? color) {
      final selected = color?.toLowerCase() == _color?.toLowerCase();
      return Tooltip(
        message: color ?? 'No color',
        child: InkResponse(
          onTap: () => setState(() => _color = color),
          radius: 20,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: parseHexColor(color) ?? colors.surfaceContainerHighest,
              border: Border.all(
                color: selected ? colors.onSurface : Colors.transparent,
                width: 2,
              ),
            ),
            child: selected
                ? Icon(
                    Icons.check,
                    size: 16,
                    color: color == null ? colors.onSurface : Colors.white,
                  )
                : null,
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(widget.list == null ? 'New list' : 'Edit list'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(labelText: 'Name', errorText: _error),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [for (final c in listColors) swatch(c), swatch(null)],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(widget.list == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}

class _TagNameDialog extends StatefulWidget {
  const _TagNameDialog({required this.tag});

  final String tag;

  @override
  State<_TagNameDialog> createState() => _TagNameDialogState();
}

class _TagNameDialogState extends State<_TagNameDialog> {
  late final _text = TextEditingController(text: widget.tag);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(
    context,
    _text.text
        .trim()
        .replaceFirst(RegExp(r'^#+'), '')
        .replaceAll(RegExp(r'\s+'), '-'),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Rename #${widget.tag}'),
    content: TextField(
      controller: _text,
      autofocus: true,
      autocorrect: false,
      decoration: const InputDecoration(prefixText: '#'),
      onSubmitted: (_) => _save(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Rename')),
    ],
  );
}
