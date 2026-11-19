import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:geas/state/background_sync.dart';
import 'package:geas/state/environment.dart';
import 'package:geas/state/home_widget.dart';
import 'package:geas/state/sync_lock.dart';
import 'package:geas_core/geas_core.dart';
import 'package:geas_core/testing.dart';

import 'harness.dart';

const _fast = Duration(milliseconds: 10);

void main() {
  tearDown(() => IsolateNameServer.removePortNameMapping(syncLockName));

  test('only one holds the lock; the next waits for its release', () async {
    final first = await SyncLock.acquire();
    var second = false;
    final waiting = SyncLock.acquire(retry: _fast).then((lock) {
      second = true;
      return lock;
    });
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(second, isFalse);

    first.release();
    final lock = await waiting;
    expect(second, isTrue);
    // A second release of the first doesn't free the new holder's lock.
    first.release();
    expect(IsolateNameServer.lookupPortByName(syncLockName), isNotNull);
    lock.release();
    expect(IsolateNameServer.lookupPortByName(syncLockName), isNull);
  });

  test('syncs under the lock run one after another', () async {
    final log = <String>[];
    Future<void> sync(String name) => withSyncLock(() async {
      log.add('$name starts');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      log.add('$name ends');
    });
    await Future.wait([sync('a'), sync('b'), sync('c')]);
    expect(log, hasLength(6));
    for (var i = 0; i < 6; i += 2) {
      expect(log[i].split(' ').first, log[i + 1].split(' ').first);
    }
  });

  test('a failed sync still releases the lock', () async {
    await expectLater(
      withSyncLock<void>(() async => throw const FormatException('no')),
      throwsFormatException,
    );
    (await SyncLock.acquire()).release();
  });

  test('a lock left by an isolate that died is taken over', () async {
    // Registered, but nothing answers, as after the holder was killed.
    final dead = ReceivePort();
    IsolateNameServer.registerPortWithName(dead.sendPort, syncLockName);
    final lock = await SyncLock.acquire(retry: _fast, ping: _fast);
    expect(
      IsolateNameServer.lookupPortByName(syncLockName),
      isNot(dead.sendPort),
    );
    lock.release();
    dead.close();
  });

  test(
    'the widget and background sync only reach GitHub under the lock',
    () async {
      final app = TestApp()..homeWidget = FakeHomeWidget();
      await app.seed();
      final github = _WatchedGitHub();
      await initDataRepo(github);
      final task = Task.create(title: 'Reply to the luthier', now: now);
      github.push({taskPath(task, now): utf8.encode(task.encode())});
      final env = AppEnvironment(
        config: app.config,
        tokens: app.tokens,
        openStore: (_) => app.local,
        connect: (_, _) => github,
        openUrl: (_) async => true,
        hostname: app.hostname,
        homeWidget: app.homeWidget,
      );

      await backgroundSync(env, clock: () => now);
      final first = backgroundSync(env, clock: () => now);
      final tick = completeFromWidget(task.id, env, clock: () => now);
      final second = backgroundSync(env, clock: () => now);
      expect(await first, BackgroundSync.synced);
      await tick;
      expect(await second, BackgroundSync.synced);

      // Each sync starts by reading the branch head.
      expect(github.lockHeld.length, greaterThanOrEqualTo(4));
      expect(github.lockHeld, everyElement(isTrue));
      final remote = Task.parse(
        utf8.decode(github.files[taskPath(task.complete(now), now)]!),
      );
      expect(remote.isCompleted, isTrue);
      expect(await app.local.readConflicts(), isEmpty);
      expect(IsolateNameServer.lookupPortByName(syncLockName), isNull);
    },
  );
}

/// Notes, at the start of each sync, whether the sync lock is held.
class _WatchedGitHub extends FakeGitHubClient {
  _WatchedGitHub() : super(repo: repo);

  final lockHeld = <bool>[];

  @override
  Future<String?> branchHead() async {
    lockHeld.add(IsolateNameServer.lookupPortByName(syncLockName) != null);
    // Long enough for another sync to start, if nothing stopped it.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return super.branchHead();
  }
}
