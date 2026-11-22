import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geas/state/desktop_background.dart';
import 'package:geas_core/geas_core.dart';
import 'package:path/path.dart' as p;

import 'harness.dart';

void main() {
  late TestApp app;
  late Directory dir;
  setUp(() async {
    app = TestApp()..homeWidget = FakeHomeWidget();
    await app.seed();
    dir = await Directory.systemTemp.createTemp('geas-bg-test-');
  });
  tearDown(() => dir.delete(recursive: true));

  group('a background start', () {
    Future<BackgroundRun> run(DateTime at) =>
        runDesktopBackgroundSync(app.environment, dir.path, clock: () => at);

    test('syncs, then waits out the interval before the next', () async {
      expect(await run(now), BackgroundRun.ran);
      final local = await Workspace.load(app.local.working);
      expect(local.tasks, isNotEmpty);

      final task = Task.create(title: 'From the phone', now: now);
      app.github.push({taskPath(task, now): utf8.encode(task.encode())});
      // Started every 15 minutes, with the interval at 30.
      expect(
        await run(now.add(const Duration(minutes: 15))),
        BackgroundRun.notDue,
      );
      expect(
        await run(now.add(const Duration(minutes: 30))),
        BackgroundRun.ran,
      );
      await local.reload();
      expect(local.tasks.map((t) => t.title), contains('From the phone'));
    });

    test(
      'does nothing when syncing on its own is off, or before setup',
      () async {
        app.config.config = app.config.config!.copyWith(backgroundSync: false);
        expect(await run(now), BackgroundRun.off);
        app.config.config = null;
        expect(await run(now), BackgroundRun.off);
        expect(File(p.join(dir.path, 'background.json')).existsSync(), isFalse);
      },
    );

    test('releases its lock, so the next start can run', () async {
      await run(now);
      final lock = await AppLock.take(dir.path);
      expect(lock, isNotNull);
      await lock!.release();
    });
  });

  group('the systemd timer on Linux', () {
    late List<String> commands;
    LinuxSystemdScheduler scheduler({
      String exe = '/opt/Geas Apps/Geas.AppImage',
    }) => LinuxSystemdScheduler(
      unitDir: p.join(dir.path, 'systemd', 'user'),
      executable: exe,
      run: (program, args) async {
        commands.add('$program ${args.join(' ')}');
        return 0;
      },
    );
    setUp(() => commands = []);
    String unit(String name) =>
        File(p.join(dir.path, 'systemd', 'user', name)).readAsStringSync();

    test('turning it on writes the units and starts the timer', () async {
      await scheduler().apply(on: true, every: const Duration(minutes: 30));
      expect(
        unit('geas-sync.service'),
        contains(
          'ExecStart="/opt/Geas Apps/Geas.AppImage" --background-sync\n',
        ),
      );
      expect(unit('geas-sync.service'), contains('Type=oneshot\n'));
      expect(unit('geas-sync.timer'), contains('OnUnitActiveSec=30min\n'));
      expect(unit('geas-sync.timer'), contains('WantedBy=timers.target\n'));
      expect(commands, [
        'systemctl --user daemon-reload',
        'systemctl --user enable --now geas-sync.timer',
        'systemctl --user restart geas-sync.timer',
      ]);

      // A new interval rewrites the timer.
      await scheduler().apply(on: true, every: const Duration(hours: 2));
      expect(unit('geas-sync.timer'), contains('OnUnitActiveSec=120min\n'));
    });

    test('turning it off stops the timer and removes the units', () async {
      await scheduler().apply(on: true, every: const Duration(minutes: 30));
      commands.clear();
      await scheduler().apply(on: false, every: const Duration(minutes: 30));
      expect(commands, [
        'systemctl --user disable --now geas-sync.timer',
        'systemctl --user daemon-reload',
      ]);
      expect(
        Directory(p.join(dir.path, 'systemd', 'user')).listSync(),
        isEmpty,
      );
      // Off when it was never on touches nothing.
      commands.clear();
      await scheduler().apply(on: false, every: const Duration(minutes: 30));
      expect(commands, isEmpty);
    });

    test('a path with a percent sign is escaped for systemd', () {
      expect(
        scheduler(exe: '/home/me/50% done/geas').serviceUnit(),
        contains('ExecStart="/home/me/50%% done/geas" --background-sync'),
      );
    });

    test('no systemd is not an error', () async {
      final broken = LinuxSystemdScheduler(
        unitDir: p.join(dir.path, 'systemd', 'user'),
        executable: '/usr/bin/geas',
        run: (program, args) async =>
            throw ProcessException(program, args, 'not found', 2),
      );
      await broken.apply(on: true, every: const Duration(minutes: 30));
    });
  });
}
