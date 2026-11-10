import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';
import 'package:go_router/go_router.dart';

import '../../state/conflicts.dart';
import '../../state/environment.dart';
import '../../state/session.dart';
import '../../state/store.dart';
import '../../state/sync.dart';
import '../tasks/due_label.dart';

/// Warn this long before the token expires.
const tokenWarning = Duration(days: 14);

/// A sentence about the token if it has expired or expires soon.
String? tokenExpiryWarning(AppConfig? config, DateTime now) {
  final expires = config?.tokenExpires;
  if (expires == null) return null;
  if (!expires.isAfter(now)) return 'The token expired. Replace it.';
  final left = expires.difference(now);
  if (left >= tokenWarning) return null;
  final days = left.inDays;
  return 'The token expires '
      '${days == 0 ? 'today' : 'in $days ${days == 1 ? 'day' : 'days'}'}. '
      'Replace it.';
}

/// "just now", "5 min ago", "3 h ago", or the day.
String syncedAgo(DateTime then, DateTime now) {
  final ago = now.difference(then);
  if (ago < const Duration(minutes: 1)) return 'just now';
  if (ago < const Duration(hours: 1)) return '${ago.inMinutes} min ago';
  if (ago < const Duration(hours: 24)) return '${ago.inHours} h ago';
  return dayLabel(LocalDate.of(then.toLocal()), now);
}

/// The sidebar's footer: how the last sync went, a button to sync now and
/// one to open settings.
class SyncStatusBar extends ConsumerWidget {
  const SyncStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncProvider);
    final config = ref.watch(configProvider).value;
    final now = ref.watch(clockProvider)();
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final warning = tokenExpiryWarning(config, now);

    final (IconData icon, String text, Color color) = switch (status) {
      SyncStatus(syncing: true) => (Icons.sync, 'Syncing…', muted),
      SyncStatus(offline: true) => (Icons.cloud_off, 'Offline', muted),
      SyncStatus(error: final _?) => (
        Icons.error_outline,
        'Sync failed',
        theme.colorScheme.error,
      ),
      SyncStatus(lastSynced: final then?) => (
        Icons.cloud_done_outlined,
        'Synced ${syncedAgo(then, now)}',
        muted,
      ),
      _ => (Icons.cloud_outlined, 'Not synced yet', muted),
    };
    final small = theme.textTheme.bodySmall!;

    final conflicts = ref.watch(conflictsProvider).value?.length ?? 0;

    void go(String location) {
      final scaffold = Scaffold.maybeOf(context);
      if (scaffold != null && scaffold.isDrawerOpen) scaffold.closeDrawer();
      context.go(location);
    }

    Widget alert(String text, String location) => Padding(
      padding: const EdgeInsets.only(right: 12, bottom: 4),
      child: InkWell(
        onTap: () => go(location),
        child: Text(
          text,
          style: small.copyWith(color: theme.colorScheme.error),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (conflicts > 0)
            alert(
              'Sync kept one side of $conflicts '
                  '${conflicts == 1 ? 'conflict' : 'conflicts'}. Review',
              '/conflicts',
            ),
          if (warning != null) alert(warning, '/settings'),
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: status.error ?? '',
                  child: Text(text, style: small.copyWith(color: color)),
                ),
              ),
              IconButton(
                tooltip: 'Sync now',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                onPressed: status.syncing
                    ? null
                    : () => ref.read(syncProvider.notifier).sync(),
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Settings',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                onPressed: () => go('/settings'),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Syncs on launch and whenever the app comes back to the foreground.
class SyncDriver extends ConsumerStatefulWidget {
  const SyncDriver({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SyncDriver> createState() => _SyncDriverState();
}

class _SyncDriverState extends ConsumerState<SyncDriver> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  void _sync() {
    if (mounted) ref.read(syncProvider.notifier).sync();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
