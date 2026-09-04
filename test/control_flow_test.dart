import 'package:khnum/khnum.dart';
import 'package:test/test.dart';

void main() {
  String render(String source, [Map<String, Object?> data = const {}]) =>
      Khnum.inMemory({'test': source}).renderSync('test', data);

  group('@if', () {
    const source = '@if(a)A@elseif(b)B@else C@endif';

    test('selects the first true branch', () {
      expect(render(source, {'a': true, 'b': false}), 'A');
      expect(render(source, {'a': false, 'b': true}), 'B');
      expect(render(source, {'a': false, 'b': false}), ' C');
    });

    test('supports nesting and spaces before arguments', () {
      expect(render('@if (a)A@endif', {'a': true}), 'A');
      expect(
        render('@if(a)@if(b)AB@else A@endif@endif', {'a': true, 'b': false}),
        ' A',
      );
    });

    test('evaluates strict expressions', () {
      expect(
        render('@if(user["age"] >= 18 && !banned)ok@endif', {
          'user': {'age': 20},
          'banned': false,
        }),
        'ok',
      );
    });

    test('requires bool and suggests an explicit collection check', () {
      expect(
        () => render('@if(items)x@endif', {'items': <Object?>[]}),
        throwsA(
          isA<TemplateRenderException>().having(
            (error) => error.message,
            'message',
            contains('isNotEmpty'),
          ),
        ),
      );
    });
  });

  group('@for', () {
    test('iterates an Iterable with a scoped value', () {
      expect(
        render('@for (final item in items)[{{ item["name"] }}]@endfor', {
          'items': [
            {'name': 'a'},
            {'name': 'b'},
          ],
        }),
        '[a][b]',
      );
    });

    test('maps are traversed explicitly through entries', () {
      expect(
        render(
          '@for (final entry in values.entries)'
          '{{ entry.key }}={{ entry.value }};@endfor',
          {
            'values': {'x': 1, 'y': 2},
          },
        ),
        'x=1;y=2;',
      );
    });

    test('null and non-iterables are errors', () {
      for (final value in [
        null,
        5,
        'text',
        {'a': 1},
      ]) {
        expect(
          () => render('@for (final item in value)x@endfor', {'value': value}),
          throwsA(isA<TemplateRenderException>()),
          reason: 'value: $value',
        );
      }
    });

    test('exposes loop metadata', () {
      const source =
          '@for (final value in values)'
          '{{ loop.iteration }}/{{ loop.count }}'
          '{{ loop.first ? "F" : "" }}{{ loop.last ? "L" : "" }} '
          '@endfor';
      expect(
        render(source, {
          'values': [1, 2, 3],
        }),
        '1/3F 2/3 3/3L ',
      );
    });

    test('exposes nested parent and depth metadata', () {
      const source =
          '@for (final outer in a)@for (final inner in b)'
          '{{ loop.parent.index }}{{ loop.index }}d{{ loop.depth }} '
          '@endfor@endfor';
      expect(
        render(source, {
          'a': [0, 1],
          'b': [0],
        }),
        '00d2 10d2 ',
      );
    });

    test('keeps values and loop metadata scoped', () {
      expect(
        render('@for (final value in values)@endfor@if(show)ok@endif', {
          'values': [],
          'show': true,
        }),
        'ok',
      );
    });
  });

  group('errors', () {
    test('unclosed block names the opener line', () {
      expect(
        () => render('line1\n@if(a)\nnever closed', {'a': true}),
        throwsA(
          isA<TemplateSyntaxException>()
              .having((error) => error.line, 'line', 2)
              .having((error) => error.template, 'template', 'test'),
        ),
      );
    });

    test('rejects a stray terminator', () {
      expect(
        () => render('x\n\n@endif'),
        throwsA(
          isA<TemplateSyntaxException>().having(
            (error) => error.line,
            'line',
            3,
          ),
        ),
      );
    });

    test('rejects legacy and incomplete loop syntax', () {
      for (final source in [
        '@foreach(items as item)@endforeach',
        '@for (item in items)@endfor',
        '@for (final item of items)@endfor',
      ]) {
        expect(
          () => render(source, {'items': []}),
          throwsA(isA<TemplateSyntaxException>()),
          reason: source,
        );
      }
    });

    test('rejects removed unless syntax with a migration hint', () {
      expect(
        () => render('@unless(value)x@endunless', {'value': false}),
        throwsA(
          isA<TemplateSyntaxException>().having(
            (error) => error.message,
            'message',
            contains('@if (!value)'),
          ),
        ),
      );
    });

    test('rejects a missing condition', () {
      expect(
        () => render('@if\nx@endif'),
        throwsA(isA<TemplateSyntaxException>()),
      );
    });
  });
}
