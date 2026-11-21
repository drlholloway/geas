import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../state/store.dart';
import '../folders/folder_actions.dart';
import '../tasks/due_label.dart';
import 'health_screen.dart';
import 'tracker_dialog.dart';

/// One tracker: how often it's logged, a bar for each recent day, and every time
/// logged, newest first, each removable. Logs now or at an earlier time.
class TrackerScreen extends ConsumerWidget {
  const TrackerScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(taskStoreProvider);
    final now = ref.watch(clockProvider)();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tracker = store.trackerById(id);
    final back = BackButton(onPressed: () => context.go('/health'));

    if (tracker == null) {
      return Scaffold(
        appBar: AppBar(leading: back, title: const Text('Health')),
        body: Center(
          child: Text(
            store.loaded ? 'This is no longer tracked.' : '',
            style: theme.textTheme.bodyLarge,
          ),
        ),
      );
    }

    final muted = theme.textTheme.bodyMedium!.copyWith(
      color: colors.onSurfaceVariant,
    );
    final stats = TrackerStats.of(tracker, now);
    final due = dueLine(tracker, now);
    final history = entryGaps(tracker);
    final every = tracker.every;
    // Sensors last days each, so a month shows too few of them.
    final chartDays = tracker.kind == TrackerKind.sensor ? 90 : 30;

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall!.copyWith(color: colors.primary),
      ),
    );

    final summary = [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                tracker.kind.label,
                if (every != null) 'every ${spanLabel(every)}',
                if (tracker.dose case final dose? when tracker.unit != null)
                  '${formatAmount(dose)} ${tracker.unit} each',
                if (stats.count > 0)
                  '${stats.count} logged since '
                      '${dayLabel(LocalDate.of(stats.first!.toLocal()), now, short: true)}',
              ].join('  ·  '),
              style: muted,
            ),
            for (final line in trackerLines(tracker, now))
              Text(line, style: muted),
            if (due != null)
              Text(
                due.text,
                style: due.overdue
                    ? muted.copyWith(
                        color: warningColor(colors),
                        fontWeight: FontWeight.w600,
                      )
                    : muted,
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => logNow(context, ref, tracker),
                  icon: const Icon(Icons.check),
                  label: Text('${tracker.kind.action} now'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _logEarlier(context, ref, tracker, now),
                  icon: const Icon(Icons.history),
                  label: const Text('Log an earlier time'),
                ),
                if (tracker.unit != null)
                  OutlinedButton.icon(
                    onPressed: () => _logAmount(context, ref, tracker),
                    icon: const Icon(Icons.scale_outlined),
                    label: const Text('A different amount'),
                  ),
              ],
            ),
          ],
        ),
      ),
      if (stats.count > 0) ...[
        heading('Last $chartDays days'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DailyBars(tracker: tracker, now: now, days: chartDays),
        ),
        heading('History'),
      ],
    ];

    return Scaffold(
      appBar: AppBar(
        leading: back,
        title: Text(tracker.name),
        actions: [
          PopupMenuButton<void>(
            tooltip: 'Options',
            itemBuilder: (_) => [
              PopupMenuItem(
                onTap: () => editTracker(context, ref, tracker),
                child: const ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit'),
                ),
              ),
              PopupMenuItem(
                onTap: () => moveToFolder(
                  context,
                  ref,
                  current: tracker.folder,
                  onPicked: (folder) => ref
                      .read(taskStoreProvider.notifier)
                      .editTracker(
                        tracker.id,
                        (t) => t.copyWith(folder: folder),
                      ),
                ),
                child: const ListTile(
                  leading: Icon(Icons.drive_file_move_outlined),
                  title: Text('Move to folder'),
                ),
              ),
              PopupMenuItem(
                onTap: () => _delete(context, ref, tracker),
                child: const ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Stop tracking'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: summary.length + history.length,
            itemBuilder: (context, i) {
              if (i < summary.length) return summary[i];
              final (:entry, :gap) = history[i - summary.length];
              final when = whenLabel(entry.at, now);
              return ListTile(
                key: ValueKey('${entry.at.toIso8601String()} ${entry.line}'),
                dense: true,
                title: Text(when),
                subtitle:
                    gap == null && entry.note == null && entry.amount == null
                    ? null
                    : Text(
                        [
                          if (entry.amount case final amount?)
                            '${formatAmount(amount)} ${tracker.unit}',
                          if (gap != null) '${spanLabel(gap)} after the last',
                          ?entry.note,
                        ].join('  ·  '),
                      ),
                trailing: IconButton(
                  tooltip: 'Remove $when',
                  iconSize: 18,
                  onPressed: () => ref
                      .read(taskStoreProvider.notifier)
                      .editTracker(tracker.id, (t) => t.withoutEntry(entry)),
                  icon: const Icon(Icons.close),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Asks how much, then logs that now in place of the usual dose.
Future<void> _logAmount(
  BuildContext context,
  WidgetRef ref,
  Tracker tracker,
) async {
  final controller = TextEditingController();
  final amount = await showDialog<double>(
    context: context,
    builder: (context) {
      void done() {
        final typed = double.tryParse(controller.text.trim());
        if (typed != null && typed > 0) Navigator.pop(context, typed);
      }

      return AlertDialog(
        title: Text('${tracker.kind.action} how much?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Amount',
            suffixText: tracker.unit,
          ),
          onSubmitted: (_) => done(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: done, child: const Text('Log')),
        ],
      );
    },
  );
  if (amount == null) return;
  ref.read(taskStoreProvider.notifier).logTracker(tracker.id, amount: amount);
}

/// Asks for a day and a time up to [now], then logs it.
Future<void> _logEarlier(
  BuildContext context,
  WidgetRef ref,
  Tracker tracker,
  DateTime now,
) async {
  final day = await showDatePicker(
    context: context,
    initialDate: now,
    firstDate: DateTime(now.year - 5),
    lastDate: now,
    helpText: 'When was ${tracker.name} ${tracker.kind.done.toLowerCase()}?',
  );
  if (day == null || !context.mounted) return;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(now),
  );
  if (time == null || !context.mounted) return;
  final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
  if (at.isAfter(now)) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('That hasn\'t happened yet.')));
    return;
  }
  ref.read(taskStoreProvider.notifier).logTracker(tracker.id, at: at);
}

Future<void> _delete(
  BuildContext context,
  WidgetRef ref,
  Tracker tracker,
) async {
  final count = tracker.entries.length;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Stop tracking ${tracker.name}?'),
      content: Text(
        count == 0
            ? 'Nothing has been logged for it.'
            : 'Its log of $count ${count == 1 ? 'time' : 'times'} is deleted '
                  'on every device.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Stop tracking'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  context.go('/health');
  ref.read(taskStoreProvider.notifier).deleteTracker(tracker.id);
}
