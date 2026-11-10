import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';

import '../../state/conflicts.dart';
import '../../state/store.dart';
import '../shell/sidebar.dart';
import '../shell/sync_status.dart';
import '../tasks/due_label.dart';

/// What sync did when two devices changed the same thing: what it kept,
/// what it set aside, and a way to swap them or let it be.
class ConflictsScreen extends ConsumerWidget {
  const ConflictsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conflicts = ref.watch(conflictsProvider).value ?? const [];
    final narrow = MediaQuery.sizeOf(context).width < sidebarBreakpoint;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Conflicts')),
      drawer: narrow ? const Drawer(child: Sidebar()) : null,
      body: conflicts.isEmpty
          ? Center(
              child: Text(
                'No conflicts.',
                style: theme.textTheme.bodyLarge!.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    'Two devices changed the same thing before syncing. '
                    'Sync kept the newer change and set the other aside.',
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final conflict in conflicts)
                  _ConflictCard(
                    key: ValueKey(
                      '${conflict.key}@${conflict.detected.toIso8601String()}',
                    ),
                    conflict: conflict,
                  ),
              ],
            ),
    );
  }
}

class _ConflictCard extends ConsumerStatefulWidget {
  const _ConflictCard({super.key, required this.conflict});

  final SyncConflict conflict;

  @override
  ConsumerState<_ConflictCard> createState() => _ConflictCardState();
}

class _ConflictCardState extends ConsumerState<_ConflictCard> {
  var _showFull = false;

  SyncConflict get _conflict => widget.conflict;

  /// The set-aside task, if it was a task and parses.
  Task? get _setAsideTask {
    final text = _conflict.setAside;
    if (text == null || !_conflict.path.endsWith('.md')) return null;
    try {
      return Task.parse(text);
    } on FormatException {
      return null;
    }
  }

  String get _summary {
    final kept = _conflict.keptLocal ? 'this device\'s' : 'the other device\'s';
    final other = _conflict.keptLocal ? 'the other device' : 'this device';
    return switch (_conflict.kind) {
      ConflictKind.fields =>
        'Both changed ${_fieldNames(_conflict.fields)}. Sync kept $kept '
            'version.',
      ConflictKind.editedAndDeleted =>
        'Deleted on $other but changed on ${_conflict.keptLocal ? 'this one' : 'the other'}. '
            'Sync kept the changed version.',
      ConflictKind.file =>
        'Both changed this file, which sync can\'t merge. Sync kept the '
            'other device\'s version.',
    };
  }

  static String _fieldNames(List<String> fields) {
    final names = [
      for (final f in fields) f == 'body' ? 'the notes' : 'the $f',
    ];
    if (names.length < 2) return names.firstOrNull ?? 'it';
    return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(taskStoreProvider);
    final now = ref.watch(clockProvider)();
    final theme = Theme.of(context);
    final conflict = _conflict;
    Task? kept;
    for (final t in store.tasks) {
      if (t.id == conflict.key) kept = t;
    }
    final setAside = _setAsideTask;
    final title = kept?.title ?? setAside?.title ?? conflict.path;
    final deletion = conflict.setAside == null;

    String value(Task task, String field) => switch (field) {
      'title' => task.title,
      'list' => store.listById(task.list)?.name ?? task.list,
      'tags' =>
        task.tags.isEmpty ? 'none' : task.tags.map((t) => '#$t').join(' '),
      'due' => task.due == null ? 'no date' : dueLabel(task.due!, now),
      'priority' => task.priority.name,
      'completed' => task.isCompleted ? 'done' : 'open',
      'body' => task.body.trim().isEmpty ? '(empty)' : task.body.trim(),
      _ => '(see the full version)',
    };

    final rows = <Widget>[];
    if (kept != null && setAside != null) {
      for (final field in conflict.fields) {
        rows.add(
          _FieldRow(
            field: field == 'body' ? 'notes' : field,
            now: value(kept, field),
            setAside: value(setAside, field),
          ),
        );
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '$_summary Found ${syncedAgo(conflict.detected, now)}.',
              style: theme.textTheme.bodySmall!.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (rows.isNotEmpty) ...[const SizedBox(height: 8), ...rows],
            if (_showFull && conflict.setAside != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  conflict.setAside!,
                  style: theme.textTheme.bodySmall!.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                if (conflict.setAside != null)
                  TextButton(
                    onPressed: () => setState(() => _showFull = !_showFull),
                    child: Text(
                      _showFull
                          ? 'Hide set-aside version'
                          : 'Show set-aside version',
                    ),
                  ),
                TextButton(
                  onPressed: () => ref
                      .read(conflictsProvider.notifier)
                      .useSetAside(conflict),
                  child: Text(
                    deletion ? 'Delete it after all' : 'Use set-aside version',
                  ),
                ),
                FilledButton.tonal(
                  onPressed: () =>
                      ref.read(conflictsProvider.notifier).dismiss(conflict),
                  child: const Text('Keep this'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.field,
    required this.now,
    required this.setAside,
  });

  final String field;
  final String now;
  final String setAside;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = theme.textTheme.labelMedium!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget side(String heading, String text, {bool struck = false}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: label),
          Text(
            text,
            style: struck
                ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
                : null,
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field[0].toUpperCase() + field.substring(1),
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              side('Now', now),
              const SizedBox(width: 16),
              side('Set aside', setAside, struck: true),
            ],
          ),
        ],
      ),
    );
  }
}
