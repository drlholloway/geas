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

  group('nesting', () {
    final health = newFolder('Health', const []);
    final diabetes = newFolder('Diabetes', [health], parent: 'health');
    final supplies =
        newFolder('Supplies', [health, diabetes], parent: 'diabetes');
    final builds = newFolder('Builds', [health, diabetes, supplies]);
    final all = [supplies, builds, diabetes, health];

    test('the parent key round-trips, and is absent at the top level', () {
      expect(health.encode(), isNot(contains('parent')));
      expect(diabetes.encode(), contains('parent: health\n'));
      expect(Folder.parse(diabetes.encode()), diabetes);
      expect(Folder.parse(diabetes.copyWith(parent: null).encode()).parent,
          isNull);
    });

    test('the tree lists each folder before what\'s inside it', () {
      expect([
        for (final (:folder, :depth) in folderTree(all)) '$depth ${folder.name}'
      ], [
        '0 Health',
        '1 Diabetes',
        '2 Supplies',
        '0 Builds'
      ]);
      expect(foldersInside('health', all), {'diabetes', 'supplies'});
      expect(foldersInside('supplies', all), isEmpty);
      expect(folderPathName(supplies, all), 'Health / Diabetes / Supplies');
    });

    test('a parent that\'s gone, or a loop, leaves a folder at the top', () {
      final orphan = health.copyWith(parent: 'deleted');
      expect(parentFolder(orphan, [orphan]), isNull);
      // Each inside the other, as two devices could leave them.
      final a = health.copyWith(parent: 'diabetes');
      final loop = [a, diabetes];
      expect(parentFolder(a, loop), isNull);
      expect(parentFolder(diabetes, loop), isNull);
      expect(folderTree(loop).map((n) => n.depth), [0, 0]);
      final self = builds.copyWith(parent: 'builds');
      expect(folderTree([self]).single.depth, 0);
    });

    test('deleting a folder moves what was in it up one level', () async {
      final area = MemoryStore().working;
      var workspace = await Workspace.load(area);
      for (final folder in all) {
        await workspace.saveFolder(folder);
      }
      await workspace.saveList(
          const TaskList(id: 'meds', name: 'Meds', folder: 'diabetes'));
      await workspace.saveTracker(
          newTracker('Insulin', const []).copyWith(folder: 'diabetes'));

      await workspace.deleteFolder('diabetes');
      workspace = await Workspace.load(area);
      expect([
        for (final (:folder, :depth) in folderTree(workspace.folders))
          '$depth ${folder.name}'
      ], [
        '0 Health',
        '1 Supplies',
        '0 Builds'
      ]);
      expect(
          workspace.lists.singleWhere((l) => l.id == 'meds').folder, 'health');
      expect(workspace.trackers.single.folder, 'health');
    });

    test('renumbering changes only the folders out of place', () {
      expect(renumberFolders([health, builds]).map((f) => (f.id, f.order)),
          [('builds', 2)]);
      expect(renumberFolders([builds, health]).map((f) => (f.id, f.order)),
          [('builds', 1), ('health', 2)]);
    });
  });
}
