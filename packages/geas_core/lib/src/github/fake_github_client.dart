import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'git_hash.dart';
import 'github_client.dart';

/// In-memory [GitHubClient] for tests: blobs, trees, commits and one branch
/// that only moves forward, like GitHub. Starts as an empty repository.
class FakeGitHubClient implements GitHubClient {
  FakeGitHubClient({this.repo = const RepoRef('owner', 'geas-data')});

  @override
  final RepoRef repo;

  @override
  final String branch = 'main';

  final _blobs = <String, List<int>>{};
  final _trees = <String, Map<String, String>>{};
  final _commits = <String, _Commit>{};
  String? _head;
  var _serial = 0;

  /// Runs at the start of each [updateBranch], so a test can push from
  /// "another device" between a sync's read and its write.
  Future<void> Function()? beforeUpdateBranch;

  /// How many blobs have been downloaded.
  int blobReads = 0;

  /// The commit at the tip of the branch.
  String? get head => _head;

  /// Files at the tip of the branch.
  Map<String, List<int>> get files => {
        for (final MapEntry(key: path, value: sha) in _headTree.entries)
          path: _blobs[sha]!,
      };

  /// Commit messages from the first commit to the tip.
  List<String> get commits {
    final messages = <String>[];
    for (var sha = _head; sha != null;) {
      final commit = _commits[sha]!;
      messages.add(commit.message);
      sha = commit.parents.isEmpty ? null : commit.parents.first;
    }
    return messages.reversed.toList();
  }

  /// Commits [changes] straight onto the branch (null deletes a file), as a
  /// hand edit on GitHub or another device would.
  void push(Map<String, List<int>?> changes, {String message = 'push'}) {
    final tree = Map.of(_headTree);
    changes.forEach((path, content) {
      if (content == null) {
        tree.remove(path);
      } else {
        tree[path] = _storeBlob(content);
      }
    });
    final head = _head;
    _head = _storeCommit(message, _storeTree(tree), [if (head != null) head]);
  }

  Map<String, String> get _headTree {
    final head = _head;
    return head == null ? const {} : _trees[_commits[head]!.tree]!;
  }

  @override
  Future<List<int>?> readFile(String path) async {
    final sha = _headTree[path];
    return sha == null ? null : _blobs[sha];
  }

  @override
  Future<void> createFile(
    String path,
    List<int> content, {
    required String message,
  }) async {
    if (_headTree.containsKey(path)) {
      throw const GitHubException(
          422, 'Invalid request. "sha" wasn\'t supplied.');
    }
    push({path: content}, message: message);
  }

  /// What [checkAccess] reports; set [access] to null for a repo the token
  /// can't see.
  RepoAccess? access = const RepoAccess(canWrite: true);

  @override
  Future<RepoAccess> checkAccess() async =>
      access ?? (throw GitHubException(404, 'Repository $repo not found.'));

  @override
  Future<String?> branchHead() async => _head;

  @override
  Future<String> commitTree(String commitSha) async => _commit(commitSha).tree;

  @override
  Future<Map<String, String>> readTree(String treeSha) async {
    final tree = _trees[treeSha];
    if (tree == null) throw GitHubException(404, 'No tree $treeSha');
    return Map.of(tree);
  }

  @override
  Future<List<int>> readBlob(String sha) async {
    final blob = _blobs[sha];
    if (blob == null) throw GitHubException(404, 'No blob $sha');
    blobReads++;
    return List.of(blob);
  }

  @override
  Future<String> createBlob(List<int> content) async => _storeBlob(content);

  @override
  Future<String> createTree(
      String baseTree, Map<String, String?> changes) async {
    final tree = Map.of(await readTree(baseTree));
    changes.forEach((path, sha) {
      if (sha == null) {
        tree.remove(path);
      } else if (!_blobs.containsKey(sha)) {
        throw GitHubException(422, 'No blob $sha');
      } else {
        tree[path] = sha;
      }
    });
    return _storeTree(tree);
  }

  @override
  Future<String> createCommit({
    required String message,
    required String tree,
    required List<String> parents,
  }) async {
    if (!_trees.containsKey(tree)) throw GitHubException(422, 'No tree $tree');
    parents.forEach(_commit);
    return _storeCommit(message, tree, parents);
  }

  @override
  Future<void> updateBranch(String commitSha) async {
    await beforeUpdateBranch?.call();
    _commit(commitSha);
    final head = _head;
    if (head != null && !_isAncestor(head, commitSha)) {
      throw const NotFastForwardException('Update is not a fast forward');
    }
    _head = commitSha;
  }

  _Commit _commit(String sha) =>
      _commits[sha] ?? (throw GitHubException(404, 'No commit $sha'));

  bool _isAncestor(String ancestor, String sha) {
    final pending = [sha];
    while (pending.isNotEmpty) {
      final next = pending.removeLast();
      if (next == ancestor) return true;
      pending.addAll(_commits[next]!.parents);
    }
    return false;
  }

  String _storeBlob(List<int> content) {
    final sha = gitBlobSha(content);
    _blobs[sha] = List.of(content);
    return sha;
  }

  String _storeTree(Map<String, String> tree) {
    final paths = tree.keys.toList()..sort();
    final sha = _hash(['tree', for (final p in paths) '$p ${tree[p]}']);
    _trees[sha] = Map.of(tree);
    return sha;
  }

  String _storeCommit(String message, String tree, List<String> parents) {
    final sha = _hash(['commit', tree, ...parents, message, '${_serial++}']);
    _commits[sha] = _Commit(message, tree, List.of(parents));
    return sha;
  }

  static String _hash(List<String> parts) =>
      sha1.convert(utf8.encode(parts.join('\n'))).toString();
}

class _Commit {
  _Commit(this.message, this.tree, this.parents);

  final String message;
  final String tree;
  final List<String> parents;
}
