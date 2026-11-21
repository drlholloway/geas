import 'dart:convert';

import 'package:geas_core/geas_core.dart';
import 'package:geas_core/testing.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 20, 12);

  test('a new folder gets an id from its name and goes last', () {
    final health = newFolder('Health', const []);
    expect(health.encode(), 'id: health\nname: Health\norder: 1\n');
    final builds = newFolder(' Pedal builds ', [health]);
    expect((builds.id, builds.name, builds.order),
        ('pedal-builds', 'Pedal builds', 2));
    expect(() => newFolder('HEALTH', [health]), throwsFormatException);
    expect(() => newFolder('!!', const []), throwsFormatException);
    expect(sortFolders([builds, health]).map((f) => f.name),
        ['Health', 'Pedal builds']);
  });

  test('a rewrite keeps comments and unknown keys', () {
    const text = '# mine\nid: health\nname: Health\nicon: heart\n';
    final folder = Folder.parse(text);
    expect(folder.encode(), text);
    expect(folder.copyWith(name: 'Body').encode(),
        '# mine\nid: health\nname: Body\nicon: heart\n');
    expect(() => Folder.parse('name: x\n'), throwsFormatException);
    expect(() => Folder.parse('id: a b\nname: x\n'), throwsFormatException);
  });

  group('the folder key', () {
    test('a list in no folder has no key; one in a folder round-trips', () {
      const list = TaskList(id: 'pedals', name: 'Pedals');
      expect(list.encode(), isNot(contains('folder')));
      final filed = TaskList.parse(list.copyWith(folder: 'builds').encode());
      expect(filed.folder, 'builds');
      expect(filed.encode(), contains('folder: builds\n'));
      expect(
          TaskList.parse(filed.copyWith(folder: null).encode()).folder, isNull);
      expect(TaskList.parse('id: a\nname: A\nfolder: ""\n').folder, isNull);
    });

    test('filters and trackers have it too', () {
      final filter = newFilter('Late', 'due:overdue', const []);
      expect(filter.encode(), isNot(contains('folder')));
      expect(
          SavedFilter.parse(filter.copyWith(folder: 'health').encode()).folder,
          'health');
      expect(filter.copyWith(folder: 'x').copyWith(name: 'Later').folder, 'x');

      final tracker = newTracker('Metformin', const []);
      expect(tracker.encode(), isNot(contains('folder')));
      final filed = Tracker.parse(tracker.copyWith(folder: 'health').encode());
      expect(filed.folder, 'health');
      expect(filed.log(now).folder, 'health');
      expect(
          Tracker.parse(filed.copyWith(folder: null).encode()).folder, isNull);
    });
  });

  test('the workspace keeps folders, and deleting one frees what was in it',
      () async {
    final area = MemoryStore().working;
    var workspace = await Workspace.load(area);
    final health = await workspace.saveFolder(newFolder('Health', const []));
    await workspace.saveFolder(newFolder('Builds', [health]));
    await workspace
        .saveList(const TaskList(id: 'meds', name: 'Meds', folder: 'health'));
    await workspace.saveList(
        const TaskList(id: 'pedals', name: 'Pedals', folder: 'builds'));
    await workspace.saveFilter(
        newFilter('Refills', '#refill', const []).copyWith(folder: 'health'));
    await workspace.saveTracker(
        newTracker('Metformin', const []).copyWith(folder: 'health'));

    workspace = await Workspace.load(area);
    expect(workspace.folders.map((f) => f.name), ['Health', 'Builds']);

    await workspace.deleteFolder('health');
    workspace = await Workspace.load(area);
    expect(workspace.folders.map((f) => f.id), ['builds']);
    expect({for (final l in workspace.lists) l.id: l.folder},
        {'inbox': null, 'meds': null, 'pedals': 'builds'});
    expect(workspace.filters.single.folder, isNull);
    expect(workspace.trackers.single.folder, isNull);
  });

  test('sync merges a rename and a reorder of the same folder', () {
    final folder = newFolder('Health', const []);
    Map<String, List<int>> file(Folder f) =>
        {folderPath(f.id): utf8.encode(f.encode())};
    final merged = mergeTrees(
      base: file(folder),
      local: file(folder.copyWith(name: 'Body')),
      remote: file(folder.copyWith(order: 5)),
      now: now,
    );
    final result =
        Folder.parse(utf8.decode(merged.files['folders/health.yaml']!));
    expect((result.name, result.order), ('Body', 5));
    expect(merged.conflicts, isEmpty);
  });

  test('renumbering trackers changes only the ones out of place', () {
    final a = newTracker('A', const []);
    final b = newTracker('B', [a]);
    final c = newTracker('C', [a, b]);
    expect(renumberTrackers([a, b, c]), isEmpty);
    final changed = renumberTrackers([a, c, b]);
    expect({for (final t in changed) t.id: t.order}, {'c': 2, 'b': 3});
  });
}
