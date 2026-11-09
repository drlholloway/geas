import 'package:geas_core/geas_core.dart';
import 'package:test/test.dart';

Task _task(String id, {DateTime? completed}) => Task(
      id: id,
      title: id,
      created: DateTime.utc(2025, 1, 1),
      updated: DateTime.utc(2025, 1, 1),
      completed: completed,
    );

void main() {
  final now = DateTime.utc(2026, 1, 15);

  test('open and recently completed tasks stay in tasks/', () {
    expect(taskPath(_task('a'), now), 'tasks/a.md');
    expect(taskPath(_task('a', completed: DateTime.utc(2025, 12, 20)), now),
        'tasks/a.md');
  });

  test('tasks done more than 30 days ago go under the year they were done', () {
    expect(taskPath(_task('a', completed: DateTime.utc(2025, 12, 1)), now),
        'archive/2025/a.md');
  });

  test('exactly 30 days is not yet archived', () {
    expect(taskPath(_task('a', completed: now.subtract(archiveAfter)), now),
        'tasks/a.md');
  });

  test('archiveMoves lists only tasks in the wrong place', () {
    final moves = archiveMoves({
      'tasks/open.md': _task('open'),
      'tasks/old.md': _task('old', completed: DateTime.utc(2025, 11, 1)),
      'archive/2025/reopened.md': _task('reopened'),
      'archive/2025/settled.md':
          _task('settled', completed: DateTime.utc(2025, 10, 1)),
    }, now);
    expect(moves, {
      'tasks/old.md': 'archive/2025/old.md',
      'archive/2025/reopened.md': 'tasks/reopened.md',
    });
  });
}
