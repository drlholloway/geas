import 'dart:io';

import 'package:geas_cli/geas_cli.dart';
import 'package:geas_core/geas_core.dart';
import 'package:test/test.dart';

const _repo = RepoRef('drl', 'geas-data');

/// Records each call and answers with [exitCode] and [stdout].
class _FakeProcesses {
  final calls = <(String, List<String>, String?)>[];
  int exitCode = 0;
  String stdout = '';

  Future<ProcessResult> call(String executable, List<String> arguments,
      {String? stdin}) async {
    calls.add((executable, arguments, stdin));
    return ProcessResult(1, exitCode, stdout, exitCode == 0 ? '' : 'nope');
  }
}

void main() {
  late _FakeProcesses run;
  setUp(() => run = _FakeProcesses());

  group('Keychain', () {
    test('writes through stdin, never the arguments', () async {
      await KeychainTokenStore(run: run.call).write(_repo, 'github_pat_abc123');
      final (exe, args, stdin) = run.calls.single;
      expect(exe, 'security');
      expect(args, ['-i']);
      expect(stdin,
          contains('add-generic-password -U -s geas -a "drl/geas-data"'));
      expect(stdin, contains('-w "github_pat_abc123"'));
    });

    test('reads the password, or null if there is none', () async {
      final store = KeychainTokenStore(run: run.call);
      run.stdout = 'github_pat_abc123\n';
      expect(await store.read(_repo), 'github_pat_abc123');
      expect(run.calls.single.$2,
          ['find-generic-password', '-s', 'geas', '-a', 'drl/geas-data', '-w']);
      run.exitCode = 44;
      expect(await store.read(_repo), isNull);
    });

    test('refuses anything that is not a token', () async {
      expect(KeychainTokenStore(run: run.call).write(_repo, 'a" ; rm -rf ~ "'),
          throwsA(isA<TokenStoreException>()));
      expect(run.calls, isEmpty);
    });

    test('reports a failed write', () async {
      run.exitCode = 1;
      expect(KeychainTokenStore(run: run.call).write(_repo, 'tok'),
          throwsA(isA<TokenStoreException>()));
    });
  });

  group('secret-tool', () {
    test('stores from stdin and looks up by repo', () async {
      final store = SecretToolTokenStore(run: run.call);
      await store.write(_repo, 'github_pat_abc123');
      expect(run.calls.single.$2, [
        'store', '--label', 'Geas token for drl/geas-data', //
        'service', 'geas', 'repo', 'drl/geas-data',
      ]);
      expect(run.calls.single.$3, 'github_pat_abc123');

      run.stdout = 'github_pat_abc123';
      expect(await store.read(_repo), 'github_pat_abc123');
      expect(run.calls.last.$2,
          ['lookup', 'service', 'geas', 'repo', 'drl/geas-data']);
    });
  });
}
