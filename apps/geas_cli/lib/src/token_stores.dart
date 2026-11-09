import 'dart:convert';
import 'dart:io';

import 'package:geas_core/geas_core.dart';

/// Runs [executable] with [arguments], writing [stdin] to it if given.
typedef RunProcess = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? stdin,
});

/// Runs a real process.
Future<ProcessResult> runProcess(
  String executable,
  List<String> arguments, {
  String? stdin,
}) async {
  final process = await Process.start(executable, arguments);
  if (stdin != null) process.stdin.write(stdin);
  await process.stdin.close();
  final out = process.stdout.transform(utf8.decoder).join();
  final err = process.stderr.transform(utf8.decoder).join();
  final code = await process.exitCode;
  return ProcessResult(process.pid, code, await out, await err);
}

const _service = 'geas';

/// Tokens in the macOS login Keychain, as generic passwords with service
/// `geas` and the repo as the account.
class KeychainTokenStore implements TokenStore {
  KeychainTokenStore({RunProcess run = runProcess}) : _run = run;

  final RunProcess _run;

  @override
  Future<String?> read(RepoRef repo) async {
    final result = await _run('security',
        ['find-generic-password', '-s', _service, '-a', '$repo', '-w']);
    if (result.exitCode != 0) return null;
    final token = (result.stdout as String).trim();
    return token.isEmpty ? null : token;
  }

  @override
  Future<void> write(RepoRef repo, String token) async {
    _checkToken(token);
    // Through `security -i` on stdin, so the token never shows up in the
    // process list.
    final result = await _run('security', ['-i'],
        stdin: 'add-generic-password -U -s $_service -a "$repo" '
            '-l "Geas token for $repo" -w "$token"\n');
    _check(result, 'save the token to the Keychain');
  }

  @override
  Future<void> delete(RepoRef repo) async {
    // 44: no such item.
    final result = await _run(
        'security', ['delete-generic-password', '-s', _service, '-a', '$repo']);
    if (result.exitCode != 44) _check(result, 'remove the token');
  }
}

/// Tokens in the Secret Service (GNOME Keyring, KWallet) via `secret-tool`.
class SecretToolTokenStore implements TokenStore {
  SecretToolTokenStore({RunProcess run = runProcess}) : _run = run;

  final RunProcess _run;

  List<String> _attributes(RepoRef repo) =>
      ['service', _service, 'repo', '$repo'];

  @override
  Future<String?> read(RepoRef repo) async {
    final result = await _run('secret-tool', ['lookup', ..._attributes(repo)]);
    if (result.exitCode != 0) return null;
    final token = (result.stdout as String).trim();
    return token.isEmpty ? null : token;
  }

  @override
  Future<void> write(RepoRef repo, String token) async {
    _checkToken(token);
    final result = await _run(
      'secret-tool',
      ['store', '--label', 'Geas token for $repo', ..._attributes(repo)],
      stdin: token,
    );
    _check(result, 'save the token with secret-tool');
  }

  @override
  Future<void> delete(RepoRef repo) async {
    await _run('secret-tool', ['clear', ..._attributes(repo)]);
  }
}

/// For platforms with neither: reads nothing and refuses to store.
class NoTokenStore implements TokenStore {
  const NoTokenStore();

  @override
  Future<String?> read(RepoRef repo) async => null;

  @override
  Future<void> write(RepoRef repo, String token) =>
      throw const TokenStoreException('There is no keychain on this system.');

  @override
  Future<void> delete(RepoRef repo) async {}
}

/// The token store for this platform.
TokenStore platformTokenStore() {
  if (Platform.isMacOS) return KeychainTokenStore();
  if (Platform.isLinux) return SecretToolTokenStore();
  return const NoTokenStore();
}

/// Saving or removing a token failed.
class TokenStoreException implements Exception {
  const TokenStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// GitHub tokens are letters, digits and underscores; anything else would
/// need quoting for `security -i`, and isn't a token.
void _checkToken(String token) {
  if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(token)) {
    throw const TokenStoreException(
        'That doesn\'t look like a GitHub token (letters, digits and _).');
  }
}

void _check(ProcessResult result, String what) {
  if (result.exitCode == 0) return;
  final detail = (result.stderr as String).trim();
  throw TokenStoreException(
      'Couldn\'t $what${detail.isEmpty ? '' : ': $detail'}.');
}
