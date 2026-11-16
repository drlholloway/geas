import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../state/store.dart';
import '../shell/sidebar.dart';
import '../tasks/due_label.dart';
import 'tracker_dialog.dart';

/// The day and time of [at] here: "Today 08:02", "Nov 12 20:15".
String whenLabel(DateTime at, DateTime now) {
  final t = at.toLocal();
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '${dayLabel(LocalDate.of(t), now, short: true)} $hh:$mm';
}

/// What [tracker]'s log says at [now], a line each: when it was last
/// logged, then how often.
List<String> trackerLines(Tracker tracker, DateTime now) {
  final stats = TrackerStats.of(tracker, now);
  final last = stats.last;
  if (last == null) return const ['Nothing logged yet'];
  final gap = stats.averageGap;
  final often = tracker.kind == TrackerKind.sensor
      ? [
          if (wearDay(tracker, now) case final day?) 'D${day.substring(1)}',
          if (gap != null) 'lasts ${spanLabel(gap)} on average',
        ]
      : [
          '${stats.today} today',
          '${oneDecimal(stats.perDayWeek!)} a day this week',
          if (stats.count > stats.week)
            '${oneDecimal(stats.perDayMonth!)} a day over 30 days',
        ];
  return [
    '${tracker.kind.done} ${spanLabel(stats.sinceLast!)} ago  ·  '
        '${whenLabel(last, now)}',
    if (often.isNotEmpty) often.join('  ·  '),
  ];
}

/// "Next due Today 20:00", or "Due since Yesterday 09:00" once that's
/// passed; null for a tracker with no `every` or nothing logged.
({String text, bool overdue})? dueLine(Tracker tracker, DateTime now) {
  final due = TrackerStats.of(tracker, now).nextDue;
  if (due == null) return null;
  final overdue = due.isBefore(now);
  return (
    text: '${overdue ? 'Due since' : 'Next due'} ${whenLabel(due, now)}',
    overdue: overdue,
  );
}

/// Logs [tracker] now and offers to undo it.
void logNow(BuildContext context, WidgetRef ref, Tracker tracker) {
  final store = ref.read(taskStoreProvider.notifier);
  final entry = store.logTracker(tracker.id);
  final now = ref.read(clockProvider)();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          '${tracker.kind.done} ${tracker.name} at ${whenLabel(entry.at, now)}',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () =>
              store.editTracker(tracker.id, (t) => t.withoutEntry(entry)),
        ),
      ),
    );
}

/// Medications, sensors and anything else logged each time it happens:
/// when each was last logged and how often, with a button to log it now.
class HealthScreen extends ConsumerWidget {
  const HealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(taskStoreProvider);
    final now = ref.watch(clockProvider)();
    final narrow = MediaQuery.sizeOf(context).width < sidebarBreakpoint;
    final theme = Theme.of(context);
    final trackers = store.trackers;

    return Scaffold(
      appBar: AppBar(title: const Text('Health')),
      drawer: narrow ? const Drawer(child: Sidebar()) : null,
      floatingActionButton: trackers.isEmpty
          ? null
          : FloatingActionButton(
              tooltip: 'Track something',
              onPressed: () => addTracker(context, ref),
              child: const Icon(Icons.add),
            ),
      body: trackers.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Nothing tracked yet.\nAdd a medication or a sensor to '
                      'log each time you take or replace it.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge!.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => addTracker(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('Track something'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              // Room for the add button over the last card.
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
              children: [
                for (final tracker in trackers)
                  Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: _TrackerCard(
                        key: ValueKey(tracker.id),
                        tracker: tracker,
                        now: now,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TrackerCard extends ConsumerWidget {
  const _TrackerCard({super.key, required this.tracker, required this.now});

  final Tracker tracker;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.bodySmall!.copyWith(
      color: colors.onSurfaceVariant,
    );
    final due = dueLine(tracker, now);
    final sensor = tracker.kind == TrackerKind.sensor;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/health/${tracker.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 12),
                    child: Icon(
                      sensor ? Icons.sensors : Icons.medication_outlined,
                      color: colors.primary,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tracker.name, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 2),
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
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: () => logNow(context, ref, tracker),
                    child: Text(tracker.kind.action),
                  ),
                ],
              ),
              if (!sensor && tracker.entries.isNotEmpty) ...[
                const SizedBox(height: 12),
                DailyBars(tracker: tracker, now: now, days: 14, height: 32),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// How many times [tracker] was logged on each of the last [days] days: one
/// thin bar a day, today on the right. Hover or long-press a bar for its
/// day and count.
class DailyBars extends StatelessWidget {
  const DailyBars({
    super.key,
    required this.tracker,
    required this.now,
    required this.days,
    this.height = 64,
  });

  final Tracker tracker;
  final DateTime now;
  final int days;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final counts = dailyCounts(tracker, now, days: days);
    final most = counts.fold(1, (m, c) => c > m ? c : m);
    final today = LocalDate.of(now);
    final label = theme.textTheme.labelSmall!.copyWith(
      color: colors.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < days; i++)
                Expanded(
                  child: Tooltip(
                    message:
                        '${dayLabel(today.addDays(i - days + 1), now, short: true)}'
                        ': ${counts[i]}',
                    waitDuration: Duration.zero,
                    child: Container(
                      // The whole column is the hover target, not just the bar.
                      height: height,
                      alignment: Alignment.bottomCenter,
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      color: Colors.transparent,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 20),
                        // A day with none still shows as a stub on the baseline.
                        height: counts[i] == 0 ? 2 : height * counts[i] / most,
                        decoration: BoxDecoration(
                          color: counts[i] == 0
                              ? colors.outlineVariant
                              : colors.primary,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              dayLabel(today.addDays(1 - days), now, short: true),
              style: label,
            ),
            Text('most in a day: $most', style: label),
            Text('Today', style: label),
          ],
        ),
      ],
    );
  }
}
