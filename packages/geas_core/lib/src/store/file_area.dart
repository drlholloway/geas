import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// A set of files keyed by repo path (`tasks/<id>.md`, always with forward
/// slashes): a device's `base/` or `working/` copy of the data repo.
abstract interface class FileArea {
  /// Every file, by path.
  Future<Map<String, List<int>>> readAll();

  /// Writes [path], replacing it if it exists. Atomic: a reader sees the old
  /// contents or the new, never part of either.
  Future<void> write(String path, List<int> content);

  /// Deletes [path] if it exists.
  Future<void> delete(String path);
}

/// Throws [ArgumentError] unless [path] is a relative repo path that stays
/// inside the area.
String checkRepoPath(String path) {
  final normalized = p.posix.normalize(path);
  if (path.isEmpty ||
      p.posix.isAbsolute(path) ||
      path.contains(r'\') ||
      normalized != path ||
      normalized == '.' ||
      normalized.startsWith('../')) {
    throw ArgumentError.value(path, 'path', 'not a relative repo path');
  }
  return path;
}

const _tmpSuffix = '.geas-tmp';
final _random = Random();

/// A [FileArea] on disk.
class DirectoryArea implements FileArea {
  DirectoryArea(this.root);

  final String root;

  File _file(String path) =>
      File(p.joinAll([root, ...checkRepoPath(path).split('/')]));

  @override
  Future<Map<String, List<int>>> readAll() async {
    final dir = Directory(root);
    if (!await dir.exists()) return {};
    final files = <String, List<int>>{};
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File || entity.path.endsWith(_tmpSuffix)) continue;
      final path = p.split(p.relative(entity.path, from: root)).join('/');
      files[path] = await entity.readAsBytes();
    }
    return files;
  }

  @override
  Future<void> write(String path, List<int> content) async {
    final file = _file(path);
    await file.parent.create(recursive: true);
    // Write beside the target, then rename over it.
    final tmp = File('${file.path}.${_random.nextInt(1 << 32)}$_tmpSuffix');
    try {
      await tmp.writeAsBytes(content, flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
  }

  @override
  Future<void> delete(String path) async {
    final file = _file(path);
    if (!await file.exists()) return;
    await file.delete();
    // Tidy up directories the delete emptied, such as an old archive year.
    var dir = file.parent;
    while (p.isWithin(root, dir.path) && await dir.list().isEmpty) {
      await dir.delete();
      dir = dir.parent;
    }
  }
}
