import 'package:test/test.dart';

import 'harness.dart';

void main() {
  late Harness geas;

  setUp(() async {
    geas = await Harness.create();
    await geas.init();
  });
  tearDown(() => geas.dispose());

  Future<void> add(List<String> args) async =>
      expect(await geas(['add', ...args]), 0, reason: '${geas.err}');

  test('prints the four quadrants by priority', () async {
    await add(['Order diodes', '-p', 'high', '-d', 'tomorrow', '-t', 'pedals']);
    await add(['Plan the build', '-p', 'medium']);
    await add(['Call back', '-p', 'low', '-d', 'today']);
    await add(['Someday', '-t', 'pedals']);

    expect(await geas(['matrix']), 0, reason: '${geas.err}');
    final out = '${geas.out}';
    expect(out, contains('Do: urgent and important (high priority)'));
    expect(
      RegExp(r'Do:.*\n.*Order diodes.*\n\nSchedule:.*\n.*Plan the build.*\n\n'
              r'Delegate:.*\n.*Call back.*\n\nDrop:.*\n.*Someday')
          .hasMatch(out),
      isTrue,
      reason: out,
    );

    expect(await geas(['matrix', '-t', '#pedals', '--no-undated']), 0);
    expect('${geas.out}', contains('Order diodes'));
    expect('${geas.out}', isNot(contains('Someday')));
    expect(
        '${geas.out}',
        contains('Schedule: important, not urgent '
            '(medium priority)\n  -\n'));
  });
}
