import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/environment.dart';
import '../../state/home_widget.dart';
import '../../state/store.dart';
import '../tasks/task_detail.dart';

/// Keeps the home-screen matrix widget in step with the tasks, opens what
/// its taps link to, and finishes tasks ticked off on it while the app is
/// running. Does nothing where there's no widget.
class HomeWidgetDriver extends ConsumerStatefulWidget {
  const HomeWidgetDriver({
    super.key,
    required this.router,
    required this.child,
  });

  final GoRouter router;
  final Widget child;

  @override
  ConsumerState<HomeWidgetDriver> createState() => _HomeWidgetDriverState();
}

class _HomeWidgetDriverState extends ConsumerState<HomeWidgetDriver> {
  /// Edits come in bursts; the widget is redrawn once they settle.
  static const _settle = Duration(milliseconds: 300);

  HomeWidgetHost? _host;
  StreamSubscription<Uri>? _clicks;
  ReceivePort? _done;
  Timer? _redraw;

  @override
  void initState() {
    super.initState();
    final host = _host = ref.read(environmentProvider).homeWidget;
    if (host == null) return;
    ref.listenManual(
      taskStoreProvider,
      (_, store) => _scheduleRedraw(store),
      fireImmediately: true,
    );
    _clicks = host.clicks.listen(_open);
    unawaited(
      host.launchedFrom().then((uri) async {
        if (uri == null) return;
        // After the router has settled on its first page, or that page
        // replaces this one.
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) _open(uri);
      }),
    );
    final done = _done = ReceivePort()..listen(_finish);
    IsolateNameServer.removePortNameMapping(donePortName);
    IsolateNameServer.registerPortWithName(done.sendPort, donePortName);
  }

  @override
  void dispose() {
    _redraw?.cancel();
    unawaited(_clicks?.cancel());
    if (_done != null) {
      IsolateNameServer.removePortNameMapping(donePortName);
      _done!.close();
    }
    super.dispose();
  }

  void _scheduleRedraw(TaskStore store) {
    if (!store.loaded) return;
    _redraw?.cancel();
    _redraw = Timer(_settle, () {
      if (!mounted) return;
      unawaited(
        showMatrix(
          _host,
          store.tasks,
          now: ref.read(clockProvider)(),
          warnDays: store.warnDays,
        ),
      );
    });
  }

  /// `geas://matrix` or `geas://task/<id>`.
  void _open(Uri uri) {
    if (uri.scheme != 'geas') return;
    final id = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
    switch (uri.host) {
      case 'matrix':
        widget.router.go('/matrix');
      case 'task' when id != null:
        widget.router.go('/matrix');
        unawaited(_openTask(id));
    }
  }

  Future<void> _openTask(String id) async {
    // On a cold start the tasks are still being read, and the sheet
    // takes its title from the task as it opens.
    await _loaded();
    await WidgetsBinding.instance.endOfFrame;
    final context = widget.router.routerDelegate.navigatorKey.currentContext;
    if (mounted && context != null && context.mounted) {
      unawaited(showTaskDetail(context, id));
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

  /// A task ticked off on the widget, as `[id, reply]`. Replies whether
  /// this app finished it; if not, the background does.
  void _finish(Object? message) {
    if (message case [final String id, final SendPort reply]) {
      final store = ref.read(taskStoreProvider);
      final known = store.loaded && store.tasks.any((t) => t.id == id);
      if (known) {
        final now = ref.read(clockProvider)();
        ref
            .read(taskStoreProvider.notifier)
            .edit(id, (t) => t.isCompleted ? t : t.complete(now));
      }
      reply.send(known);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
