import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';

import '../../state/environment.dart';
import '../../state/session.dart';
import '../../state/store.dart';
import '../../state/sync.dart';

/// The same three steps as `geas setup`: name this device, make or pick the
/// private data repo, and make a token that can reach only that repo.
///
/// With [replaceToken], only the token step, for the repo already set up.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key, this.replaceToken = false});

  final bool replaceToken;

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  late final TextEditingController _device;
  late final TextEditingController _owner;
  late final TextEditingController _name;
  final _token = TextEditingController();
  var _busy = false;
  String? _error;

  /// A link the browser didn't open, shown to copy instead.
  Uri? _unopened;

  @override
  void initState() {
    super.initState();
    final config = ref.read(configProvider).value;
    _device = TextEditingController(
      text: config?.device ?? ref.read(environmentProvider).hostname,
    );
    _owner = TextEditingController(text: config?.repo.owner ?? '');
    _name = TextEditingController(text: config?.repo.name ?? 'geas-data');
    for (final c in [_device, _owner, _name, _token]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_device, _owner, _name, _token]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The repo as typed so far, or null if it isn't a valid name yet.
  RepoRef? get _repo {
    try {
      return RepoRef.parse('${_owner.text.trim()}/${_name.text.trim()}');
    } on FormatException {
      return null;
    }
  }

  String get _deviceName => _device.text.trim();

  Future<void> _open(Uri url) async {
    final opened = await ref.read(environmentProvider).openUrl(url);
    if (mounted) setState(() => _unopened = opened ? null : url);
  }

  Future<void> _connect() async {
    final repo = _repo;
    final token = _token.text.trim();
    if (repo == null || _deviceName.isEmpty || token.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(configProvider.notifier)
          .connect(repo: repo, device: _deviceName, token: token);
      if (!mounted) return;
      if (widget.replaceToken) {
        unawaited(ref.read(syncProvider.notifier).sync());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Token replaced. Delete the old one on GitHub under Settings, '
              'Developer settings, Personal access tokens.',
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } on TokenProblem catch (e) {
      _fail(e.message);
    } on Exception catch (e) {
      _fail(
        isNetworkError(e)
            ? 'Couldn\'t reach GitHub. Check the connection and try again.'
            : describeSyncError(e, repo),
      );
    }
  }

  void _fail(String message) {
    if (mounted) {
      setState(() {
        _busy = false;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = _repo;
    final token = _token.text.trim();
    final ready =
        !_busy && repo != null && _deviceName.isNotEmpty && token.isNotEmpty;
    final today = LocalDate.of(ref.watch(clockProvider)());
    final replace = widget.replaceToken;

    final steps = <Widget>[
      if (!replace) ...[
        _Step(
          number: 1,
          title: 'This device',
          children: [
            TextField(
              controller: _device,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Device name',
                helperText: 'Names this device in sync commits.',
              ),
            ),
          ],
        ),
        _Step(
          number: 2,
          title: 'The data repo',
          children: [
            Text(
              'A private GitHub repo holds your tasks. Already have one? '
              'Fill in its name and go on to step 3.',
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _owner,
                    enabled: !_busy,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'GitHub account',
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 16, 8, 0),
                  child: Text('/'),
                ),
                Expanded(
                  child: TextField(
                    controller: _name,
                    enabled: !_busy,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Repo'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: repo == null || _busy
                  ? null
                  : () => _open(newRepoUrl(repo)),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Create it on GitHub'),
            ),
            const SizedBox(height: 4),
            Text(
              'The form is filled in. Check it says Private, then click '
              '"Create repository".',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ],
      _Step(
        number: replace ? null : 3,
        title: replace ? 'A new token for $repo' : 'A token for this device',
        children: [
          const Text(
            'Each device has its own token that can reach only the data '
            'repo. GitHub\'s form comes filled in with the name, a one-year '
            'expiry and the permission (Contents: read and write). GitHub '
            'can\'t pick the repo for you, so:',
          ),
          const SizedBox(height: 8),
          _Numbered(
            1,
            'Under "Repository access", choose "Only select repositories" '
            'and pick ${repo ?? 'the repo'}.',
          ),
          const _Numbered(2, 'Click "Generate token" and copy it.'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: repo == null || _deviceName.isEmpty || _busy
                ? null
                : () => _open(newTokenUrl(repo, _deviceName, today)),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Open the token form'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _token,
            enabled: !_busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Paste the token'),
            onSubmitted: (_) => ready ? _connect() : null,
          ),
          if (token.startsWith('ghp_')) ...[
            const SizedBox(height: 8),
            Text(
              'That\'s a classic token, which can reach every repo you can. '
              'A fine-grained token limited to ${repo ?? 'the data repo'} '
              'is safer.',
              style: theme.textTheme.bodySmall!.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    ];

    return Scaffold(
      appBar: replace ? AppBar(title: const Text('Replace the token')) : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!replace) ...[
                    Text(
                      'Set up Geas',
                      style: theme.textTheme.headlineMedium!.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Geas keeps your tasks in a private GitHub repo, and '
                      'each device syncs with its own token that can reach '
                      'only that repo.',
                    ),
                  ],
                  ...steps,
                  if (_unopened != null) ...[
                    const SizedBox(height: 16),
                    const Text('The browser didn\'t open. Copy this link:'),
                    SelectableText('$_unopened'),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: ready ? _connect : null,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(replace ? 'Replace' : 'Connect'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({this.number, required this.title, required this.children});

  final int? number;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (number != null) ...[
                CircleAvatar(
                  radius: 13,
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  child: Text(
                    '$number',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _Numbered extends StatelessWidget {
  const _Numbered(this.number, this.text);

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 8, top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 20, child: Text('$number.')),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
