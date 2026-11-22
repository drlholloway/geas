import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/session.dart';
import '../../state/store.dart';

/// Folders collapsed in the sidebar, by id. Kept in this device's config,
/// so they're still closed the next time the app opens.
class CollapsedFolders extends Notifier<Set<String>> {
  @override
  Set<String> build() => {
    ...?ref.watch(configProvider.select((c) => c.value?.collapsedFolders)),
  };

  void toggle(String id) {
    final next = state.contains(id) ? ({...state}..remove(id)) : {...state, id};
    state = next;
    final config = ref.read(configProvider).value;
    if (config != null) {
      unawaited(
        ref
            .read(configProvider.notifier)
            .save(config.copyWith(collapsedFolders: next.toList()..sort())),
      );
    }
  }
}

final collapsedFoldersProvider =
    NotifierProvider<CollapsedFolders, Set<String>>(CollapsedFolders.new);

/// Asks for a new folder's name and adds it. Returns it, or null if
/// cancelled.
Future<Folder?> addFolder(BuildContext context, WidgetRef ref) async {
  final created = await showDialog<Folder>(
    context: context,
    builder: (context) => _FolderNameDialog(
      title: 'New folder',
      action: 'Add',
      onSave: (name) => newFolder(name, ref.read(taskStoreProvider).folders),
    ),
  );
  if (created != null) ref.read(taskStoreProvider.notifier).saveFolder(created);
  return created;
}

/// Asks which folder something goes in, [current] being where it is now,
/// then calls [onPicked] with the folder's id, or null for no folder.
/// A new folder can be made on the spot.
Future<void> moveToFolder(
  BuildContext context,
  WidgetRef ref, {
  required String? current,
  required void Function(String? folderId) onPicked,
  Set<String> except = const {},
  String none = 'No folder',
}) async {
  final all = ref.read(taskStoreProvider).folders;
  // Leaving out [except], as a folder can't go inside itself.
  final tree = [
    for (final node in folderTree(all))
      if (!except.contains(node.folder.id)) node,
  ];
  final folders = [for (final node in tree) node.folder];
  // The folder's id, '' for none, or null for a new one.
  final choice = await showDialog<(String?,)>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Move to folder'),
      children: [
        for (final (:folder, :depth) in tree)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, (folder.id,)),
            child: Row(
              children: [
                SizedBox(width: 20.0 * depth),
                Icon(
                  folder.id == current ? Icons.check : Icons.folder_outlined,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(folder.name)),
              ],
            ),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, (null,)),
          child: const Row(
            children: [
              Icon(Icons.create_new_folder_outlined, size: 20),
              SizedBox(width: 12),
              Text('New folder…'),
            ],
          ),
        ),
        if (current != null && folders.any((f) => f.id == current))
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ('',)),
            child: Row(
              children: [
                const Icon(Icons.folder_off_outlined, size: 20),
                const SizedBox(width: 12),
                Text(none),
              ],
            ),
          ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice.$1) {
    case '':
      onPicked(null);
    case final id?:
      onPicked(id);
    case null:
      final created = await addFolder(context, ref);
      if (created != null) onPicked(created.id);
  }
}

/// The menu on a folder's heading in the sidebar: rename or delete it.
class FolderMenu extends ConsumerWidget {
  const FolderMenu({super.key, required this.folder});

  final Folder folder;

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final renamed = await showDialog<Folder>(
      context: context,
      builder: (context) => _FolderNameDialog(
        title: 'Rename folder',
        action: 'Save',
        initial: folder.name,
        onSave: (name) {
          final others = ref
              .read(taskStoreProvider)
              .folders
              .where((f) => f.id != folder.id);
          if (others.any((f) => f.name.toLowerCase() == name.toLowerCase())) {
            throw FormatException('There is already a folder called "$name".');
          }
          return folder.copyWith(name: name);
        },
      ),
    );
    if (renamed != null) {
      ref.read(taskStoreProvider.notifier).saveFolder(renamed);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete the folder ${folder.name}?'),
        content: const Text(
          'What\'s in it isn\'t deleted: its lists, filters and trackers go '
          'back to being in no folder.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete folder'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(taskStoreProvider.notifier).deleteFolder(folder.id);
    }
  }

  /// Puts this folder inside another, or back at the top level.
  Future<void> _move(BuildContext context, WidgetRef ref) {
    final store = ref.read(taskStoreProvider);
    return moveToFolder(
      context,
      ref,
      current: parentFolder(folder, store.folders)?.id,
      except: {folder.id, ...foldersInside(folder.id, store.folders)},
      none: 'Top level',
      onPicked: (parent) => ref
          .read(taskStoreProvider.notifier)
          .saveFolder(folder.copyWith(parent: parent)),
    );
  }

  /// Shows this folder and the ones beside it, to drag into order.
  Future<void> _reorder(BuildContext context, WidgetRef ref) =>
      showDialog<void>(
        context: context,
        builder: (context) => _ReorderFoldersDialog(folder: folder),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<void>(
    tooltip: '${folder.name} folder options',
    iconSize: 18,
    padding: EdgeInsets.zero,
    itemBuilder: (_) => [
      PopupMenuItem(
        onTap: () => _move(context, ref),
        child: const ListTile(
          leading: Icon(Icons.drive_file_move_outlined),
          title: Text('Move into folder'),
        ),
      ),
      PopupMenuItem(
        onTap: () => _reorder(context, ref),
        child: const ListTile(
          leading: Icon(Icons.swap_vert),
          title: Text('Reorder folders'),
        ),
      ),
      PopupMenuItem(
        onTap: () => _rename(context, ref),
        child: const ListTile(
          leading: Icon(Icons.edit_outlined),
          title: Text('Rename folder'),
        ),
      ),
      PopupMenuItem(
        onTap: () => _delete(context, ref),
        child: const ListTile(
          leading: Icon(Icons.delete_outline),
          title: Text('Delete folder'),
        ),
      ),
    ],
  );
}

/// [folder] and the folders at its level, each with a handle to drag it
/// into place.
class _ReorderFoldersDialog extends ConsumerWidget {
  const _ReorderFoldersDialog({required this.folder});

  final Folder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(taskStoreProvider).folders;
    final parent = parentFolder(folder, all)?.id;
    final siblings = sortFolders(
      all.where((f) => parentFolder(f, all)?.id == parent),
    );
    return AlertDialog(
      title: const Text('Reorder folders'),
      content: SizedBox(
        width: 320,
        child: ReorderableListView(
          shrinkWrap: true,
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) {
            final ids = [for (final f in siblings) f.id];
            ids.insert(to, ids.removeAt(from));
            ref.read(taskStoreProvider.notifier).reorderFolders(ids);
          },
          children: [
            for (final (index, f) in siblings.indexed)
              ListTile(
                key: ValueKey(f.id),
                dense: true,
                leading: const Icon(Icons.folder_outlined, size: 20),
                title: Text(f.name),
                trailing: ReorderableDragStartListener(
                  index: index,
                  child: Tooltip(
                    message: 'Drag ${f.name}',
                    child: const MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog({
    required this.title,
    required this.action,
    required this.onSave,
    this.initial,
  });

  final String title, action;
  final String? initial;

  /// Makes the folder to save, throwing [FormatException] if it can't be.
  final Folder Function(String name) onSave;

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final _name = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    try {
      Navigator.pop(context, widget.onSave(name));
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _name,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(labelText: 'Folder name', errorText: _error),
      onSubmitted: (_) => _save(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _name.text.trim().isEmpty ? null : _save,
        child: Text(widget.action),
      ),
    ],
  );
}
