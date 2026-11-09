/// Task priority, lowest first, so `index` orders them.
enum Priority {
  none,
  low,
  medium,
  high;

  /// Parses the frontmatter form (`none`, `low`, `medium`, `high`, any case).
  static Priority parse(String text) {
    final lower = text.trim().toLowerCase();
    for (final p in values) {
      if (p.name == lower) return p;
    }
    throw FormatException(
      'Priority must be none, low, medium or high, got "$text".',
    );
  }
}
