import 'package:geas_core/geas_core.dart';
import 'package:test/test.dart';

String? _merge(String base, String local, String remote) {
  final result = mergeLines(base, local, remote);
  return result.conflict ? null : result.text;
}

void main() {
  const base = 'one\ntwo\nthree\nfour\nfive\n';

  test('one side changed', () {
    expect(_merge(base, 'one\n2\nthree\nfour\nfive\n', base),
        'one\n2\nthree\nfour\nfive\n');
    expect(_merge(base, base, 'one\ntwo\nthree\nfour\n'),
        'one\ntwo\nthree\nfour\n');
  });

  test('edits to separate lines combine', () {
    expect(
      _merge(base, 'ONE\ntwo\nthree\nfour\nfive\n',
          'one\ntwo\nthree\nfour\nFIVE\n'),
      'ONE\ntwo\nthree\nfour\nFIVE\n',
    );
  });

  test('additions at different places combine', () {
    expect(
      _merge(base, 'zero\none\ntwo\nthree\nfour\nfive\n',
          'one\ntwo\nthree\nfour\nfive\nsix\n'),
      'zero\none\ntwo\nthree\nfour\nfive\nsix\n',
    );
  });

  test('a deletion and an edit elsewhere combine', () {
    expect(
      _merge(
          base, 'one\nthree\nfour\nfive\n', 'one\ntwo\nthree\nfour\nfive!\n'),
      'one\nthree\nfour\nfive!\n',
    );
  });

  test('the same edit on both sides is not a conflict', () {
    expect(
      _merge(base, 'one\nTWO\nthree\nfour\nfive\n',
          'one\nTWO\nthree\nfour\nfive\n'),
      'one\nTWO\nthree\nfour\nfive\n',
    );
  });

  test('different edits to the same line conflict', () {
    expect(
      mergeLines(base, 'one\n2\nthree\nfour\nfive\n',
              'one\nzwei\nthree\nfour\nfive\n')
          .conflict,
      isTrue,
    );
  });

  test('different additions at the same place conflict', () {
    expect(
      mergeLines(base, '${base}local\n', '${base}remote\n').conflict,
      isTrue,
    );
  });

  test('checking different checklist items combines', () {
    const list = '- [ ] a\n- [ ] b\n- [ ] c\n';
    expect(
      _merge(
          list, '- [x] a\n- [ ] b\n- [ ] c\n', '- [ ] a\n- [ ] b\n- [x] c\n'),
      '- [x] a\n- [ ] b\n- [x] c\n',
    );
  });

  test('checking neighboring checklist items combines', () {
    const list = '- [ ] a\n- [ ] b\n';
    expect(_merge(list, '- [x] a\n- [ ] b\n', '- [ ] a\n- [x] b\n'),
        '- [x] a\n- [x] b\n');
  });

  test('neighboring lines: the same line changed differently conflicts', () {
    expect(mergeLines('a\nb\n', 'A\nb\n', 'a2\nB\n').conflict, isTrue);
  });

  test('both added from an empty base', () {
    expect(_merge('', 'same\n', 'same\n'), 'same\n');
    expect(mergeLines('', 'a\n', 'b\n').conflict, isTrue);
  });
}
