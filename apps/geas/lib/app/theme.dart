import 'package:flutter/material.dart';
import 'package:geas_core/geas_core.dart';

const _seed = Color(0xFF2E6F6A);

ThemeData buildTheme(Brightness brightness) => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
  listTileTheme: const ListTileThemeData(minVerticalPadding: 6),
);

/// The checkbox outline for a task: red, amber or blue by priority.
Color priorityColor(Priority priority, ColorScheme colors) =>
    switch (priority) {
      Priority.high => const Color(0xFFD64545),
      Priority.medium => const Color(0xFFE0A030),
      Priority.low => const Color(0xFF4A84D6),
      Priority.none => colors.outline,
    };

/// A list color such as `#4a90d9`, or null if it's missing or malformed.
Color? parseHexColor(String? text) {
  if (text == null) return null;
  final hex = text.startsWith('#') ? text.substring(1) : text;
  if (hex.length != 6) return null;
  final value = int.tryParse(hex, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}

/// Amber for a task close to its due date, readable on either theme.
Color warningColor(ColorScheme colors) => colors.brightness == Brightness.light
    ? const Color(0xFFB56A00)
    : const Color(0xFFFFB74D);

/// A task title's style for its [warning]: bold amber when approaching, the
/// error color when overdue.
TextStyle? dueWarningStyle(DueWarning warning, ColorScheme colors) =>
    switch (warning) {
      DueWarning.none => null,
      DueWarning.approaching => TextStyle(
        color: warningColor(colors),
        fontWeight: FontWeight.w600,
      ),
      DueWarning.overdue => TextStyle(color: colors.error),
    };
