import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';
import 'package:go_router/go_router.dart';

import '../../state/environment.dart';
import '../../state/session.dart';
import '../../state/store.dart';
import '../../state/sync.dart';
import '../shell/sidebar.dart';
import '../shell/sync_status.dart';
import '../tasks/due_label.dart';

/// The data repo, this device, the token and sync, with ways to replace
/// the token or disconnect.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider).value;
    final status = ref.watch(syncProvider);
    final now = ref.watch(clockProvider)();
    final theme = Theme.of(context);
    final narrow = MediaQuery.sizeOf(context).width < sidebarBreakpoint;
    if (config == null) return const Scaffold();

    final expires = config.tokenExpires;
    final warning = tokenExpiryWarning(config, now);
    final syncLine = switch (status) {
      SyncStatus(syncing: true) => 'Syncing…',
      SyncStatus(error: final error?) => error,
      SyncStatus(lastSynced: final then?) => 'Synced ${syncedAgo(then, now)}',
      _ => 'Not synced yet',
    };

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.labelLarge!.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      drawer: narrow ? const Drawer(child: Sidebar()) : null,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          heading('Sync'),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Data repo'),
            subtitle: Text('${config.repo}'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => ref
                .read(environmentProvider)
                .openUrl(
                  Uri.https(
                    'github.com',
                    '/${config.repo.owner}/${config.repo.name}',
                  ),
                ),
          ),
          ListTile(
            leading: const Icon(Icons.devices_outlined),
            title: const Text('This device'),
            subtitle: Text(config.device),
          ),
          ListTile(
            leading: Icon(
              status.error == null
                  ? Icons.cloud_done_outlined
                  : Icons.sync_problem,
            ),
            title: const Text('Last sync'),
            subtitle: Text(
              [
                syncLine,
                if (status.conflicts > 0)
                  'Sync kept one side of ${status.conflicts} '
                      '${status.conflicts == 1 ? 'conflict' : 'conflicts'}; '
                      'the other is saved in conflicts.json.',
              ].join(' '),
            ),
            trailing: TextButton(
              onPressed: status.syncing
                  ? null
                  : () => ref.read(syncProvider.notifier).sync(),
              child: const Text('Sync now'),
            ),
          ),
          heading('Token'),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('GitHub token'),
            subtitle: Text(
              warning ??
                  (expires == null
                      ? 'Stored on this device.'
                      : 'Expires '
                            '${dayLabel(LocalDate.of(expires.toLocal()), now)}.'),
              style: warning == null
                  ? null
                  : TextStyle(color: theme.colorScheme.error),
            ),
            trailing: FilledButton.tonal(
              onPressed: () => context.push('/settings/token'),
              child: const Text('Replace'),
            ),
          ),
          if (status.fixInSettings)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Sync can\'t use the token. Replace it with a new one.',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          heading('This device'),
          ListTile(
            leading: Icon(Icons.link_off, color: theme.colorScheme.error),
            title: Text(
              'Disconnect',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            subtitle: const Text(
              'Stop syncing and forget the token. Tasks stay in the repo.',
            ),
            onTap: () => _disconnect(context, ref, config.repo),
          ),
        ],
      ),
    );
  }

  Future<void> _disconnect(
    BuildContext context,
    WidgetRef ref,
    RepoRef repo,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect this device?'),
        content: Text(
          'It stops syncing with $repo and forgets its token. Edits not yet '
          'synced stay on this device until you connect again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (yes ?? false) {
      await ref.read(syncProvider.notifier).sync();
      await ref.read(configProvider.notifier).disconnect();
    }
  }
}
