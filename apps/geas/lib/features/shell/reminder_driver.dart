import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/environment.dart';
import '../../state/reminders.dart';
import '../../state/session.dart';
import '../../state/store.dart';

/// Keeps this device's reminders in step with the tasks and trackers, and
/// with whether reminders are turned on. Does nothing where there's no way
/// to show them.
class ReminderDriver extends ConsumerStatefulWidget {
  const ReminderDriver({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ReminderDriver> createState() => _ReminderDriverState();
}

class _ReminderDriverState extends ConsumerState<ReminderDriver> {
  /// Edits come in bursts; reminders are set once they settle.
  static const _settle = Duration(milliseconds: 500);

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (ref.read(environmentProvider).reminders == null) return;
    ref.listenManual(
      taskStoreProvider,
      (_, _) => _soon(),
      fireImmediately: true,
    );
    ref.listenManual(
      configProvider.select((c) => c.value?.reminders ?? false),
      (_, _) => _soon(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _soon() {
    _timer?.cancel();
    _timer = Timer(_settle, () {
      final store = ref.read(taskStoreProvider);
      if (!mounted || !store.loaded) return;
      unawaited(
        scheduleReminders(
          ref.read(environmentProvider).reminders,
          on: ref.read(configProvider).value?.reminders ?? false,
          tasks: store.tasks,
          trackers: store.trackers,
          now: ref.read(clockProvider)(),
        ).catchError((Object e) => debugPrint('geas: reminders: $e')),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
