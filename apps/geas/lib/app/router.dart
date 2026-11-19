import 'package:flutter/foundation.dart';
import 'package:geas_core/geas_core.dart';
import 'package:go_router/go_router.dart';

import '../features/conflicts/conflicts_screen.dart';
import '../features/health/health_screen.dart';
import '../features/health/tracker_screen.dart';
import '../features/matrix/matrix_screen.dart';
import '../features/orders/orders_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/setup/setup_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/tasks/task_list_screen.dart';
import '../features/tasks/task_view.dart';

/// One router per app instance (a global would keep its location across
/// widget tests).
GoRouter createRouter() => GoRouter(
  initialLocation: '/list/$inboxId',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/list/:id',
          builder: (c, s) => TaskListScreen(
            view: TaskView(ViewKind.list, s.pathParameters['id']!),
          ),
        ),
        GoRoute(
          path: '/today',
          builder: (c, s) =>
              const TaskListScreen(view: TaskView(ViewKind.today)),
        ),
        GoRoute(
          path: '/week',
          builder: (c, s) =>
              const TaskListScreen(view: TaskView(ViewKind.week)),
        ),
        GoRoute(
          path: '/tag/:tag',
          builder: (c, s) => TaskListScreen(
            view: TaskView(ViewKind.tag, s.pathParameters['tag']!),
          ),
        ),
        GoRoute(path: '/orders', builder: (c, s) => const OrdersScreen()),
        GoRoute(path: '/health', builder: (c, s) => const HealthScreen()),
        GoRoute(
          path: '/health/:id',
          builder: (c, s) => TrackerScreen(id: s.pathParameters['id']!),
        ),
        GoRoute(path: '/search', builder: (c, s) => const SearchScreen()),
        GoRoute(
          path: '/filter/:id',
          builder: (c, s) => SearchScreen(
            // A new screen for each filter, so its query field starts over.
            key: ValueKey(s.pathParameters['id']),
            filterId: s.pathParameters['id'],
          ),
        ),
        GoRoute(path: '/matrix', builder: (c, s) => const MatrixScreen()),
        GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
        GoRoute(path: '/conflicts', builder: (c, s) => const ConflictsScreen()),
      ],
    ),
    GoRoute(
      path: '/settings/token',
      builder: (c, s) => const SetupScreen(replaceToken: true),
    ),
  ],
);
