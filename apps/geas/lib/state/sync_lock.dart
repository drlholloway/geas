import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

/// The name the isolate that is syncing holds, so no other one starts.
const syncLockName = 'geas.sync.lock';

/// Held by whichever part of the app is syncing this device's copy: the app
/// itself, the home-screen widget's background work, or Android's periodic
/// background sync. They run in separate isolates of one process, and a
/// sync reads the copy, talks to GitHub, then writes it back, so two at
/// once could each undo what the other pulled.
///
/// The lock is a port registered under [syncLockName]; registering is
/// atomic, so only one isolate gets it. The holder answers pings on that
/// port. If the holder's isolate was killed mid-sync its registration is
/// left behind, but nothing answers, and the next one to ask takes over.
class SyncLock {
  SyncLock._(this._port);

  final ReceivePort _port;
  var _held = true;

  /// Waits until no one else is syncing, then holds the lock. Checks again
  /// every [retry]; a holder that doesn't answer within [ping] is taken to
  /// be gone.
  static Future<SyncLock> acquire({
    Duration retry = const Duration(milliseconds: 200),
    Duration ping = const Duration(seconds: 1),
  }) async {
    while (true) {
      final port = ReceivePort();
      if (IsolateNameServer.registerPortWithName(port.sendPort, syncLockName)) {
        port.listen((message) {
          if (message is SendPort) message.send(true);
        });
        return SyncLock._(port);
      }
      port.close();
      final holder = IsolateNameServer.lookupPortByName(syncLockName);
      // Released between the two calls: try again at once.
      if (holder == null) continue;
      if (await _answers(holder, ping)) {
        await Future<void>.delayed(retry);
      } else if (IsolateNameServer.lookupPortByName(syncLockName) == holder) {
        // Still the one that didn't answer, not a new holder.
        IsolateNameServer.removePortNameMapping(syncLockName);
      }
    }
  }

  static Future<bool> _answers(SendPort holder, Duration wait) async {
    final reply = ReceivePort();
    try {
      holder.send(reply.sendPort);
      return await reply.first.timeout(wait) == true;
    } on TimeoutException {
      return false;
    } finally {
      reply.close();
    }
  }

  /// Lets the next one sync. Safe to call twice.
  void release() {
    if (!_held) return;
    _held = false;
    if (IsolateNameServer.lookupPortByName(syncLockName) == _port.sendPort) {
      IsolateNameServer.removePortNameMapping(syncLockName);
    }
    _port.close();
  }
}

/// Runs [sync] once no other isolate is syncing.
Future<T> withSyncLock<T>(Future<T> Function() sync) async {
  final lock = await SyncLock.acquire();
  try {
    return await sync();
  } finally {
    lock.release();
  }
}
