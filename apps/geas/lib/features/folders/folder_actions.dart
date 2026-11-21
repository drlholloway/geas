import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/store.dart';

/// Folders collapsed in the sidebar, by id. Kept while the app runs.
class CollapsedFolders extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String id) =>
      state = state.contains(id) ? ({...state}..remove(id)) : {...state, id};
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
}) async {
  final folders = ref.read(taskStoreProvider).folders;
  // The folder's id, '' for none, or null for a new one.
  final choice = await showDialog<(String?,)>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Move to folder'),
      children: [
        for (final folder in folders)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, (folder.id,)),
            child: Row(
              children: [
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
            child: const Row(
              children: [
                Icon(Icons.folder_off_outlined, size: 20),
                SizedBox(width: 12),
                Text('No folder'),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<void>(
    tooltip: '${folder.name} folder options',
    iconSize: 18,
    padding: EdgeInsets.zero,
    itemBuilder: (_) => [
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
