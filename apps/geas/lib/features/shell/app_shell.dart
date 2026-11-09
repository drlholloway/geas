import 'package:flutter/material.dart';

import 'sidebar.dart';

/// At desktop widths, the sidebar beside the current screen. On a phone the
/// screen shows the sidebar as its drawer instead.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < sidebarBreakpoint) return child;
    return Material(
      child: Row(
        children: [
          SizedBox(
            width: 260,
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: const Sidebar(),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}
