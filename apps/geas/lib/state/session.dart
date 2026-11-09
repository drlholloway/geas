import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geas_core/geas_core.dart';

import 'environment.dart';

/// The data repo this device is set up for, or null before setup.
class ConfigNotifier extends AsyncNotifier<AppConfig?> {
  @override
  Future<AppConfig?> build() => ref.read(environmentProvider).config.load();

  Future<void> save(AppConfig? config) async {
    await ref.read(environmentProvider).config.save(config);
    state = AsyncData(config);
  }

  /// Makes [repo] this device's data repo, after checking [token] can push
  /// to it: writes `geas.yaml` if the repo has none, stores the token and
  /// saves the config. Throws [TokenProblem] with advice for a token that
  /// won't do.
  Future<void> connect({
    required RepoRef repo,
    required String device,
    required String token,
  }) async {
    final env = ref.read(environmentProvider);
    final client = env.connect(repo, token);
    final access = await checkTokenAccess(client);
    await initDataRepo(client);
    await env.tokens.write(repo, token);
    await save(
      AppConfig(repo: repo, device: device, tokenExpires: access.tokenExpires),
    );
  }

  /// Forgets the repo and this device's token. The local copy stays, so
  /// connecting again only syncs what changed.
  Future<void> disconnect() async {
    final config = state.value;
    if (config == null) return;
    await ref.read(environmentProvider).tokens.delete(config.repo);
    await save(null);
  }
}

final configProvider = AsyncNotifierProvider<ConfigNotifier, AppConfig?>(
  ConfigNotifier.new,
);

/// The data repo and the local copy of it, once set up.
class Session {
  const Session({
    required this.repo,
    required this.device,
    required this.store,
  });

  final RepoRef repo;
  final String device;
  final SyncStore store;
}

/// Rebuilt only when the repo or device changes, not when a new token's
/// expiry is saved.
final sessionProvider = Provider<Session?>((ref) {
  final key = ref.watch(
    configProvider.select(
      (c) => switch (c.value) {
        final config? => (config.repo, config.device),
        null => null,
      },
    ),
  );
  if (key == null) return null;
  final (repo, device) = key;
  return Session(
    repo: repo,
    device: device,
    store: ref.read(environmentProvider).openStore(repo),
  );
});
