import 'package:geas/state/store.dart';
import 'package:geas_core/geas_core.dart';

/// Tasks for widget tests, pushed to the fake data repo. Due dates are
/// relative to [now] so every section has something in it.
TaskStore sampleStore(DateTime now) {
  final today = LocalDate.of(now);
  Due on(int days) => Due.date(today.addDays(days));
  var age = 0;
  Task task(
    String title, {
    String list = inboxId,
    List<String> tags = const [],
    Due? due,
    Priority priority = Priority.none,
    String body = '',
  }) => Task.create(
    title: title,
    now: now.subtract(Duration(hours: 5 * ++age)),
    list: list,
    tags: tags,
    due: due,
    priority: priority,
    body: body,
  );

  // Twice a day for three weeks with a few missed, and this morning's.
  final morning = DateTime(now.year, now.month, now.day, 8, 5);
  var metformin = Tracker(id: 'metformin', name: 'Metformin', order: 1);
  for (var day = 20; day >= 0; day--) {
    final at = morning.subtract(Duration(days: day));
    if (day % 9 != 4) metformin = metformin.log(at);
    if (day > 0 && day % 6 != 2) {
      metformin = metformin.log(at.add(const Duration(hours: 12, minutes: 20)));
    }
  }
  var sensor = Tracker(
    id: 'cgm-sensor',
    name: 'CGM sensor',
    kind: TrackerKind.sensor,
    every: const Duration(days: 10),
    order: 2,
  );
  for (final day in [33, 24, 14, 4]) {
    sensor = sensor.log(morning.subtract(Duration(days: day, hours: -1)));
  }

  return TaskStore(
    trackers: [metformin, sensor],
    lists: const [
      TaskList(id: 'pedals', name: 'Pedals', color: '#E07A2F', order: 1),
      TaskList(id: 'home', name: 'Home', color: '#3C8DBC', order: 2),
    ],
    tasks: [
      task(
        'Order 1N914s',
        list: 'pedals',
        tags: ['tayda', 'pedals'],
        due: on(0),
        priority: Priority.high,
        body:
            'Need about 20 for the next two builds.\n\n'
            '- [ ] check Tayda stock\n- [x] pick pots\n- [ ] order enclosures\n',
      ),
      task(
        'Renew car registration',
        list: 'home',
        due: on(-2),
        priority: Priority.medium,
      ),
      task('Call the dentist', due: Due.at(today, 17, 0), tags: ['errands']),
      task(
        'Draft the Geas sync design',
        tags: ['geas'],
        due: on(1),
        priority: Priority.medium,
        body: 'Three-way merge per task, never a textual git merge.\n',
      ),
      task('Reply to the luthier', priority: Priority.low),
      task(
        'Pick up bass strings',
        list: 'pedals',
        tags: ['errands'],
        due: on(3),
      ),
      task('Clean the gutters', list: 'home', due: on(10)),
      task('Fix the squeaky door', list: 'home'),
      task(
        'Solder the fuzz board',
        list: 'pedals',
        tags: ['pedals'],
      ).complete(now.subtract(const Duration(days: 1))),
    ],
  );
}
