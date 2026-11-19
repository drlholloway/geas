import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/store.dart';
import '../shell/sidebar.dart';
import '../tasks/task_tile.dart';

/// Finds tasks by what's typed: words in the title or notes, `#tag`,
/// `^list`, `!high`, `due:today` and `is:done`. A search can be saved as a
/// filter, which then has its own entry in the sidebar; with [filterId]
/// this is that filter's screen.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.filterId});

  /// The saved filter being shown, or null for a fresh search.
  final String? filterId;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _query = TextEditingController();

  /// Whether the saved filter's query has been put in the field yet; it
  /// isn't there to read until the local copy has loaded.
  var _filled = false;

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = await _askName(context, title: 'Save as a filter');
    if (name == null || !mounted) return;
    final SavedFilter filter;
    try {
      filter = newFilter(
        name,
        _query.text,
        ref.read(taskStoreProvider).filters,
      );
    } on FormatException catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    ref.read(taskStoreProvider.notifier).saveFilter(filter);
    context.go('/filter/${filter.id}');
  }

  Future<void> _rename(SavedFilter filter) async {
    final name = await _askName(
      context,
      title: 'Rename filter',
      initial: filter.name,
    );
    if (name == null) return;
    ref
        .read(taskStoreProvider.notifier)
        .saveFilter(filter.copyWith(name: name));
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(taskStoreProvider);
    final now = ref.watch(clockProvider)();
    final theme = Theme.of(context);
    final narrow = MediaQuery.sizeOf(context).width < sidebarBreakpoint;
    final filter = switch (widget.filterId) {
      final id? => store.filterById(id),
      null => null,
    };
    if (filter != null && !_filled) {
      _filled = true;
      _query.text = filter.query;
    }

    final query = TaskQuery.parse(_query.text, lists: store.lists);
    final typed = _query.text.trim();
    // A fresh search shows nothing until something is typed; a filter
    // shows what it matches, even if that's every open task.
    final results = query.isEmpty && filter == null
        ? const <Task>[]
        : query.search(store.tasks, now);
    final changed = filter != null && typed != filter.query;
    final store_ = ref.read(taskStoreProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(filter?.name ?? 'Search'),
        actions: [
          if (filter == null && !query.isEmpty)
            IconButton(
              tooltip: 'Save as a filter',
              onPressed: _save,
              icon: const Icon(Icons.bookmark_add_outlined),
            ),
          if (changed)
            TextButton(
              onPressed: () => store_.saveFilter(filter.copyWith(query: typed)),
              child: const Text('Update filter'),
            ),
          if (filter != null)
            PopupMenuButton<void>(
              tooltip: 'Filter options',
              itemBuilder: (_) => [
                PopupMenuItem(
                  onTap: () => _rename(filter),
                  child: const ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Rename filter'),
                  ),
                ),
                PopupMenuItem(
                  onTap: () {
                    context.go('/search');
                    store_.deleteFilter(filter.id);
                  },
                  child: const ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('Delete filter'),
                  ),
                ),
              ],
            ),
        ],
      ),
      drawer: narrow ? const Drawer(child: Sidebar()) : null,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _query,
              autofocus: filter == null,
              autocorrect: false,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search tasks',
                helperText:
                    'Words, #tag, ^list, !high, due:today, due:week, '
                    'due:overdue, due:none, is:done, is:all',
                helperMaxLines: 2,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        onPressed: _query.clear,
                        icon: const Icon(Icons.close),
                      ),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
            ),
          ),
          if (widget.filterId != null && filter == null && store.loaded)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: Text('This filter was deleted.')),
            )
          else if (!query.isEmpty || filter != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                switch (results.length) {
                  0 => 'No tasks match.',
                  1 => '1 task',
                  final n => '$n tasks',
                },
                style: theme.textTheme.titleSmall!.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          for (final task in results)
            TaskTile(key: ValueKey(task.id), task: task),
        ],
      ),
    );
  }
}

/// Asks for a filter's name; null if cancelled or left empty.
Future<String?> _askName(
  BuildContext context, {
  required String title,
  String? initial,
}) async {
  final controller = TextEditingController(text: initial);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (text) => Navigator.pop(context, text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}
