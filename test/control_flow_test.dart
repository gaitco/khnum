import 'package:maat_khnum_core/maat_khnum_core.dart';
import 'package:test/test.dart';

void main() {
  String render(String src, [Map<String, Object?> data = const {}]) =>
      Khnum.inMemory({'t': src}).renderSync('t', data);

  group('@if', () {
    const src = '@if(a)A@elseif(b)B@else C@endif';
    test('if', () => expect(render(src, {'a': true, 'b': false}), 'A'));
    test('elseif', () => expect(render(src, {'a': false, 'b': 1}), 'B'));
    test('else', () => expect(render(src, {'a': 0, 'b': ''}), ' C'));
    test(
      'without else',
      () => expect(render('@if(a)A@endif', {'a': null}), ''),
    );
    test('space before parens', () {
      expect(render('@if (a)A@endif', {'a': true}), 'A');
    });
    test('nested', () {
      expect(
        render('@if(a)@if(b)AB@else A@endif@endif', {'a': 1, 'b': 0}),
        ' A',
      );
    });
    test('expressions', () {
      expect(
        render('@if(user.age >= 18 && !banned)ok@endif', {
          'user': {'age': 20},
          'banned': false,
        }),
        'ok',
      );
    });
  });

  group('@unless', () {
    test('renders when false', () {
      expect(render('@unless(x)no@else yes@endunless', {'x': false}), 'no');
      expect(render('@unless(x)no@else yes@endunless', {'x': true}), ' yes');
    });
  });

  group('@foreach', () {
    test('lists', () {
      expect(
        render('@foreach(items as item)[{{ item.name }}]@endforeach', {
          'items': [
            {'name': 'a'},
            {'name': 'b'},
          ],
        }),
        '[a][b]',
      );
    });
    test('maps with key => value', () {
      expect(
        render('@foreach(m as k => v){{ k }}={{ v }};@endforeach', {
          'm': {'x': 1, 'y': 2},
        }),
        'x=1;y=2;',
      );
    });
    test('list index as key', () {
      expect(
        render('@foreach(l as i => v){{ i }}{{ v }}@endforeach', {
          'l': ['a', 'b'],
        }),
        '0a1b',
      );
    });
    test('null iterates zero times', () {
      expect(render('@foreach(l as v)x@endforeach', {'l': null}), '');
    });
    test('loop variable', () {
      const src =
          '@foreach(l as v){{ loop.iteration }}/{{ loop.count }}'
          '{{ loop.first ? "F" : "" }}{{ loop.last ? "L" : "" }} @endforeach';
      expect(
        render(src, {
          'l': [1, 2, 3],
        }),
        '1/3F 2/3 3/3L ',
      );
    });
    test('nested loop.parent and depth', () {
      const src =
          '@foreach(a as x)@foreach(b as y)'
          '{{ loop.parent.index }}{{ loop.index }}d{{ loop.depth }} '
          '@endforeach@endforeach';
      expect(
        render(src, {
          'a': [0, 1],
          'b': [0],
        }),
        '00d2 10d2 ',
      );
    });
    test('loop variable is scoped to the loop', () {
      expect(
        render('@foreach(l as v)@endforeach@if(x)ok@endif', {'l': [], 'x': 1}),
        'ok',
      );
    });
    test('iterating a non-collection is an error', () {
      expect(
        () => render('@foreach(n as v)@endforeach', {'n': 5}),
        throwsA(isA<TemplateRenderException>()),
      );
    });
  });

  group('@for', () {
    test('item in items', () {
      expect(
        render('@for(i in nums){{ i }},@endfor', {
          'nums': [1, 2],
        }),
        '1,2,',
      );
    });
    test('has loop variable', () {
      expect(
        render('@for(i in nums){{ loop.index }}@endfor', {
          'nums': [7, 8],
        }),
        '01',
      );
    });
  });

  group('errors', () {
    test('unclosed block names the opener line', () {
      expect(
        () => render('line1\n@if(a)\nnever closed'),
        throwsA(
          isA<TemplateSyntaxException>()
              .having((e) => e.line, 'line', 2)
              .having((e) => e.template, 'template', 't'),
        ),
      );
    });
    test('stray @endif', () {
      expect(
        () => render('x\n\n@endif'),
        throwsA(
          isA<TemplateSyntaxException>().having((e) => e.line, 'line', 3),
        ),
      );
    });
    test('bad foreach syntax', () {
      expect(
        () => render('@foreach(items)@endforeach'),
        throwsA(isA<TemplateSyntaxException>()),
      );
    });
    test('missing condition', () {
      expect(
        () => render('@if\nx@endif'),
        throwsA(isA<TemplateSyntaxException>()),
      );
    });
  });
}
