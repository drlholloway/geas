import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/environment.dart';
import '../../state/reminders.dart';
import '../../state/session.dart';
import '../../state/store.dart';
import '../tasks/task_detail.dart';

/// Keeps this device's reminders in step with the tasks and trackers, with
/// whether reminders are turned on, and with what other devices have
/// dismissed. A tap on a reminder dismisses it everywhere and opens what
/// it's about. Does nothing where there's no way to show reminders.
class ReminderDriver extends ConsumerStatefulWidget {
  const ReminderDriver({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<ReminderDriver> createState() => _ReminderDriverState();
}

class _ReminderDriverState extends ConsumerState<ReminderDriver> {
  /// Edits come in bursts; reminders are set once they settle.
  static const _settle = Duration(milliseconds: 500);

  Timer? _timer;
  StreamSubscription<ReminderTap>? _taps;

  @override
  void initState() {
    super.initState();
    final host = ref.read(environmentProvider).reminders;
    if (host == null) return;
    ref.listenManual(
      taskStoreProvider,
      (_, _) => _soon(),
      fireImmediately: true,
    );
    ref.listenManual(
      configProvider.select(
        (c) => (c.value?.reminders ?? false, c.value?.reminderMinutes),
      ),
      (_, _) => _soon(),
    );
    _taps = host.taps.listen(_tapped);
    unawaited(
      host.launchedFrom().then((tap) {
        if (tap != null && mounted) _tapped(tap);
      }),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_taps?.cancel());
    super.dispose();
  }

  void _soon() {
    _timer?.cancel();
    _timer = Timer(_settle, () {
      final store = ref.read(taskStoreProvider);
      if (!mounted || !store.loaded) return;
      final config = ref.read(configProvider).value;
      unawaited(
        scheduleReminders(
          ref.read(environmentProvider).reminders,
          on: config?.reminders ?? false,
          tasks: store.tasks,
          trackers: store.trackers,
          now: ref.read(clockProvider)(),
          dayMinutes: config?.reminderMinutes ?? reminderHour * 60,
          dismissed: store.dismissals,
        ).catchError((Object e) => debugPrint('geas: reminders: $e')),
      );
    });
  }

  /// A reminder was tapped: it's acknowledged, here and on every device
  /// once they sync, and what it's about opens.
  Future<void> _tapped(ReminderTap tap) async {
    await _loaded();
    // After the router has settled on its first page, when the tap is what
    // launched the app, or that page replaces this one.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    ref.read(taskStoreProvider.notifier).dismissReminder(tap.key, tap.at);
    final colon = tap.key.indexOf(':');
    final kind = tap.key.substring(0, colon < 0 ? 0 : colon);
    final id = tap.key.substring(colon + 1);
    final store = ref.read(taskStoreProvider);
    if (kind == 'tracker' && store.trackerById(id) != null) {
      widget.router.go('/health/$id');
    } else if (kind == 'task' && store.tasks.any((t) => t.id == id)) {
      widget.router.go('/today');
      await WidgetsBinding.instance.endOfFrame;
      final context = widget.router.routerDelegate.navigatorKey.currentContext;
      if (mounted && context != null && context.mounted) {
        unawaited(showTaskDetail(context, id));
      }
    }
  }

  /// Completes once the local copy has been read.
  Future<void> _loaded() {
    if (ref.read(taskStoreProvider).loaded) return Future.value();
    final loaded = Completer<void>();
    late final ProviderSubscription<TaskStore> watch;
    watch = ref.listenManual(taskStoreProvider, (_, store) {
      if (store.loaded && !loaded.isCompleted) {
        loaded.complete();
        watch.close();
      }
    });
    return loaded.future;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
