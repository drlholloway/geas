import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';

import '../../app/theme.dart';
import '../../state/store.dart';
import '../shell/sidebar.dart';
import '../tasks/task_tile.dart';

/// Below this width the quadrants start out as tabs instead of a 2x2 grid.
const _gridBreakpoint = 640.0;

/// How the matrix lays out its quadrants.
enum MatrixLayout {
  /// All four on one screen.
  grid,

  /// One at a time, as tabs.
  tabs,
}

/// The layout chosen with the switch on the Matrix screen, or null to go
/// by the width. Kept while the app runs.
class MatrixLayoutNotifier extends Notifier<MatrixLayout?> {
  @override
  MatrixLayout? build() => null;

  void choose(MatrixLayout layout) => state = layout;
}

final matrixLayoutProvider =
    NotifierProvider<MatrixLayoutNotifier, MatrixLayout?>(
      MatrixLayoutNotifier.new,
    );

/// The Eisenhower matrix: open tasks in four quadrants, one per priority.
/// Dragging a task to another quadrant sets its priority.
class MatrixScreen extends ConsumerStatefulWidget {
  const MatrixScreen({super.key});

  @override
  ConsumerState<MatrixScreen> createState() => _MatrixScreenState();
}

class _MatrixScreenState extends ConsumerState<MatrixScreen> {
  String? _list;
  String? _tag;
  var _includeUndated = true;

  void _move(String id, Quadrant to) => ref
      .read(taskStoreProvider.notifier)
      .edit(id, (t) => t.copyWith(priority: to.priority));

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(taskStoreProvider);
    final now = ref.watch(clockProvider)();
    final narrow = MediaQuery.sizeOf(context).width < sidebarBreakpoint;
    final tags = allTags(store.tasks);
    // A filter for a list or tag that's gone shows everything.
    final list = store.listById(_list ?? '') == null ? null : _list;
    final tag = tags.contains(_tag) ? _tag : null;
    final matrix = matrixOf(
      store.tasks,
      now: now,
      list: list,
      tag: tag,
      includeUndated: _includeUndated,
    );

    final filters = Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DropdownMenu<String?>(
          key: const ValueKey('list-filter'),
          initialSelection: list,
          label: const Text('List'),
          width: 180,
          dropdownMenuEntries: [
            const DropdownMenuEntry(value: null, label: 'All lists'),
            for (final l in store.lists)
              DropdownMenuEntry(value: l.id, label: l.name),
          ],
          onSelected: (v) => setState(() => _list = v),
        ),
        DropdownMenu<String?>(
          key: const ValueKey('tag-filter'),
          initialSelection: tag,
          label: const Text('Tag'),
          width: 180,
          dropdownMenuEntries: [
            const DropdownMenuEntry(value: null, label: 'All tags'),
            for (final t in tags) DropdownMenuEntry(value: t, label: '#$t'),
          ],
          onSelected: (v) => setState(() => _tag = v),
        ),
        FilterChip(
          label: const Text('Undated'),
          tooltip: 'Include tasks with no due date',
          selected: _includeUndated,
          onSelected: (v) => setState(() => _includeUndated = v),
        ),
      ],
    );

    Widget quadrant(Quadrant q) => _QuadrantView(
      quadrant: q,
      tasks: matrix[q]!,
      longPress: narrow,
      onDrop: (id) => _move(id, q),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final chosen = ref.watch(matrixLayoutProvider);
        final layout =
            chosen ??
            (constraints.maxWidth >= _gridBreakpoint
                ? MatrixLayout.grid
                : MatrixLayout.tabs);
        final layoutSwitch = Padding(
          padding: const EdgeInsets.only(right: 8),
          child: SegmentedButton<MatrixLayout>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(
                value: MatrixLayout.grid,
                icon: Icon(Icons.grid_view, size: 18),
                tooltip: 'All four on one screen',
              ),
              ButtonSegment(
                value: MatrixLayout.tabs,
                icon: Icon(Icons.view_carousel_outlined, size: 18),
                tooltip: 'One quadrant at a time',
              ),
            ],
            selected: {layout},
            onSelectionChanged: (s) =>
                ref.read(matrixLayoutProvider.notifier).choose(s.single),
          ),
        );
        // Tighter spacing when four boxes share a small screen.
        final gap = constraints.maxWidth >= _gridBreakpoint ? 12.0 : 8.0;
        if (layout == MatrixLayout.grid) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Matrix'),
              actions: [layoutSwitch],
            ),
            drawer: narrow ? const Drawer(child: Sidebar()) : null,
            body: Padding(
              padding: EdgeInsets.fromLTRB(gap, 4, gap, gap),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  filters,
                  SizedBox(height: gap),
                  Expanded(
                    child: Column(
                      children: [
                        for (final row in [
                          [Quadrant.doFirst, Quadrant.schedule],
                          [Quadrant.delegate, Quadrant.drop],
                        ]) ...[
                          if (row.first != Quadrant.doFirst)
                            SizedBox(height: gap),
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: quadrant(row[0])),
                                SizedBox(width: gap),
                                Expanded(child: quadrant(row[1])),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        // One quadrant per tab.
        return DefaultTabController(
          length: Quadrant.values.length,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Matrix'),
              actions: [layoutSwitch],
              bottom: TabBar(
                tabs: [
                  for (final q in Quadrant.values)
                    Tab(text: '${q.title} ${matrix[q]!.length}'),
                ],
              ),
            ),
            drawer: narrow ? const Drawer(child: Sidebar()) : null,
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: filters,
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      for (final q in Quadrant.values)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: quadrant(q),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QuadrantView extends StatelessWidget {
  const _QuadrantView({
    required this.quadrant,
    required this.tasks,
    required this.longPress,
    required this.onDrop,
  });

  final Quadrant quadrant;
  final List<Task> tasks;

  /// Start a drag with a long press (touch) rather than a plain drag.
  final bool longPress;
  final void Function(String id) onDrop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tint = priorityColor(quadrant.priority, colors);

    return DragTarget<Task>(
      onWillAcceptWithDetails: (d) => d.data.priority != quadrant.priority,
      onAcceptWithDetails: (d) => onDrop(d.data.id),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return Material(
          key: ValueKey('quadrant-${quadrant.name}'),
          color: hovering
              ? tint.withValues(alpha: 0.12)
              : colors.surfaceContainerLow,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: hovering ? tint : colors.outlineVariant,
              width: hovering ? 2 : 1,
            ),
          ),
          // A small box, as on a phone, drops the subtitle and tightens
          // the task rows.
          child: LayoutBuilder(
            builder: (context, box) {
              final compact = box.maxWidth < 280;
              final title = Text(
                quadrant.title,
                overflow: TextOverflow.ellipsis,
                style:
                    (compact
                            ? theme.textTheme.titleSmall!
                            : theme.textTheme.titleMedium!)
                        .copyWith(color: tint, fontWeight: FontWeight.w600),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 10 : 16,
                      compact ? 8 : 12,
                      compact ? 10 : 16,
                      4,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.flag, size: compact ? 16 : 18, color: tint),
                        SizedBox(width: compact ? 6 : 8),
                        if (compact)
                          Expanded(child: title)
                        else ...[
                          Flexible(child: title),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              quadrant.subtitle,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall!.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        Text(
                          '${tasks.length}',
                          style: theme.textTheme.labelLarge!.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: tasks.isEmpty
                        ? Center(
                            child: Text(
                              'Nothing here.',
                              style: theme.textTheme.bodyMedium!.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.only(bottom: 8),
                            children: [
                              for (final task in tasks)
                                _DraggableTask(
                                  key: ValueKey(task.id),
                                  task: task,
                                  longPress: longPress,
                                  compact: compact,
                                ),
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _DraggableTask extends StatelessWidget {
  const _DraggableTask({
    super.key,
    required this.task,
    required this.longPress,
    required this.compact,
  });

  final Task task;
  final bool longPress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tile = TaskTile(task: task, compact: compact);
    final feedback = Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(task.title),
      ),
    );
    final placeholder = Opacity(opacity: 0.4, child: tile);
    return longPress
        ? LongPressDraggable<Task>(
            data: task,
            feedback: feedback,
            childWhenDragging: placeholder,
            child: tile,
          )
        : Draggable<Task>(
            data: task,
            feedback: feedback,
            childWhenDragging: placeholder,
            child: tile,
          );
  }
}
