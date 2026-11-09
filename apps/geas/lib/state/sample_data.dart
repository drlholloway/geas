import 'package:geas_core/geas_core.dart';

import 'store.dart';

/// Tasks to look at until the app syncs with the data repo. Due dates are
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

  return TaskStore(
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
