import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';

import '../../state/store.dart';

/// Asks what to track, then adds it.
Future<void> addTracker(BuildContext context, WidgetRef ref) async {
  final created = await showDialog<Tracker>(
    context: context,
    builder: (context) => _TrackerDialog(
      onSave: (name, kind, every) => newTracker(
        name,
        ref.read(taskStoreProvider).trackers,
        kind: kind,
        every: every,
      ),
    ),
  );
  if (created != null) {
    ref.read(taskStoreProvider.notifier).saveTracker(created);
  }
}

/// Edits [tracker]'s name, kind and how often it's due.
Future<void> editTracker(
  BuildContext context,
  WidgetRef ref,
  Tracker tracker,
) async {
  final edited = await showDialog<Tracker>(
    context: context,
    builder: (context) => _TrackerDialog(
      tracker: tracker,
      onSave: (name, kind, every) {
        final others = ref
            .read(taskStoreProvider)
            .trackers
            .where((t) => t.id != tracker.id);
        if (others.any((t) => t.name.toLowerCase() == name.toLowerCase())) {
          throw FormatException('"$name" is already tracked.');
        }
        return tracker.copyWith(name: name, kind: kind, every: every);
      },
    ),
  );
  if (edited == null) return;
  ref
      .read(taskStoreProvider.notifier)
      .editTracker(
        tracker.id,
        (t) => t.copyWith(
          name: edited.name,
          kind: edited.kind,
          every: edited.every,
        ),
      );
}

class _TrackerDialog extends StatefulWidget {
  const _TrackerDialog({this.tracker, required this.onSave});

  /// The tracker being edited, or null for a new one.
  final Tracker? tracker;

  /// Makes the tracker to save, throwing [FormatException] if it can't be.
  final Tracker Function(String name, TrackerKind kind, Duration? every) onSave;

  @override
  State<_TrackerDialog> createState() => _TrackerDialogState();
}

class _TrackerDialogState extends State<_TrackerDialog> {
  late final _name = TextEditingController(text: widget.tracker?.name);
  late final _every = TextEditingController(
    text: switch (widget.tracker?.every) {
      null => '',
      final every => formatInterval(every),
    },
  );
  late var _kind = widget.tracker?.kind ?? TrackerKind.med;
  String? _nameError, _everyError;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() => _nameError = null));
    _every.addListener(() => setState(() => _everyError = null));
  }

  @override
  void dispose() {
    _name.dispose();
    _every.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Duration? every;
    if (_every.text.trim().isNotEmpty) {
      try {
        every = parseInterval(_every.text);
      } on FormatException {
        setState(() => _everyError = 'Like 12h, 10d or 2w');
        return;
      }
    }
    try {
      Navigator.pop(context, widget.onSave(name, _kind, every));
    } on FormatException catch (e) {
      setState(() => _nameError = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sensor = _kind == TrackerKind.sensor;
    return AlertDialog(
      title: Text(widget.tracker == null ? 'Track something' : 'Edit'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Name',
                hintText: sensor ? 'CGM sensor' : 'Metformin',
                errorText: _nameError,
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<TrackerKind>(
              segments: const [
                ButtonSegment(
                  value: TrackerKind.med,
                  icon: Icon(Icons.medication_outlined),
                  label: Text('Medication'),
                ),
                ButtonSegment(
                  value: TrackerKind.sensor,
                  icon: Icon(Icons.sensors),
                  label: Text('Sensor'),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (kinds) =>
                  setState(() => _kind = kinds.single),
            ),
            const SizedBox(height: 4),
            Text(
              sensor
                  ? 'Replaced every several days. Shows how long each lasted.'
                  : 'Taken once or more a day. Shows how many a day.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextField(
              controller: _every,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: sensor ? 'Replace every' : 'Take every',
                hintText: sensor ? '10d; optional' : '12h; optional',
                errorText: _everyError,
              ),
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty ? null : _save,
          child: Text(widget.tracker == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}
