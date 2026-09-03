import 'dart:io';

import 'package:maat_khnum_core/maat_khnum_core.dart';
import 'package:test/test.dart';

void main() {
  group('view names cannot leave the views directory', () {
    late Directory dir;
    late Khnum khnum;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('khnum_sec');
      File('${dir.path}/views/ok.khnum.html')
        ..createSync(recursive: true)
        ..writeAsStringSync('ok');
      File('${dir.path}/secret.khnum.html').writeAsStringSync('SECRET');
      khnum = Khnum(viewsPath: '${dir.path}/views');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    for (final name in [
      '../secret',
      '..\\secret',
      '/etc/passwd',
      'ok/../../secret',
      '..',
      'a..b',
      '.hidden',
      '',
      'ok.',
      'ok ',
      'views/../secret',
    ]) {
      test("rejects '$name'", () {
        expect(
          () => khnum.renderSync(name),
          throwsA(isA<TemplateNotFoundException>()),
        );
      });
    }

    test('the same rule applies to @include, @extends and components', () {
      final mem = Khnum.inMemory({
        'a': '@include("../secret")',
        'b': '@extends("/etc/passwd")',
        'c': '<x-../secret />',
      });
      expect(
        () => mem.renderSync('a'),
        throwsA(isA<TemplateNotFoundException>()),
      );
      expect(
        () => mem.renderSync('b'),
        throwsA(isA<TemplateNotFoundException>()),
      );
      // Not a legal component name, so it is plain text, not a lookup.
      expect(mem.renderSync('c'), '<x-../secret />');
    });

    test('valid nested names still work', () {
      expect(khnum.renderSync('ok'), 'ok');
    });
  });

  group('recursion', () {
    test('self include hits maxDepth with a clear message', () {
      final khnum = Khnum.inMemory({'a': 'x@include("a")'}, maxDepth: 10);
      expect(
        () => khnum.renderSync('a'),
        throwsA(
          isA<TemplateRenderException>()
              .having(
                (e) => e.message,
                'message',
                contains('Maximum render depth'),
              )
              .having((e) => e.template, 'template', 'a'),
        ),
      );
    });
    test('mutual recursion through a component', () {
      final khnum = Khnum.inMemory({
        'a': '<x-b />',
        'components.b': '@include("a")',
      }, maxDepth: 5);
      expect(
        () => khnum.renderSync('a'),
        throwsA(isA<TemplateRenderException>()),
      );
    });
    test('a layout that extends itself', () {
      final khnum = Khnum.inMemory({'a': '@extends("a")'}, maxDepth: 3);
      expect(
        () => khnum.renderSync('a'),
        throwsA(isA<TemplateRenderException>()),
      );
    });
    test('legitimate nesting below the limit is fine', () {
      final khnum = Khnum.inMemory({
        'a': '@foreach(items as i)<x-b :n="i" />@endforeach',
        'components.b': '@if(n > 0)<x-b :n="n - 1" />@endif{{ n }}',
      });
      expect(
        khnum.renderSync('a', {
          'items': [3],
        }),
        '0123',
      );
    });
  });

  group('output safety', () {
    String render(String src, Map<String, Object?> data) =>
        Khnum.inMemory({'t': src}).renderSync('t', data);

    test('user data never becomes markup through {{ }}', () {
      final payloads = [
        '<script>alert(1)</script>',
        '"><img src=x onerror=alert(1)>',
        "' onmouseover='alert(1)",
        '&lt;already&gt;',
      ];
      for (final p in payloads) {
        final out = render('<p title="{{ v }}">{{ v }}</p>', {'v': p});
        expect(out, isNot(contains('<script')));
        expect(out, isNot(contains('<img')));
        expect(out, isNot(contains('"><'))); // attribute never closes early
        expect(out, isNot(contains("' onmouseover")));
      }
    });
    test('objects are escaped through toString, not trusted', () {
      expect(render('{{ v }}', {'v': _Evil()}), '&lt;b&gt;');
    });
    test('the attributes bag escapes bound values', () {
      final khnum = Khnum.inMemory({
        't': '<x-c :title="v" />',
        'components.c': '<a {{ attributes }}>',
      });
      expect(
        khnum.renderSync('t', {'v': '"><b>'}),
        '<a title="&quot;&gt;&lt;b&gt;">',
      );
    });
    test('templates cannot call arbitrary methods on data', () {
      expect(
        () => render('{{ f.readAsStringSync() }}', {'f': File('/etc/passwd')}),
        throwsA(isA<TemplateRenderException>()),
      );
      expect(
        () => render('{{ f.path }}', {'f': File('/etc/passwd')}),
        throwsA(isA<TemplateRenderException>()),
      );
    });
    test('division by zero is a render error, not a crash', () {
      expect(
        () => render('{{ 1 % 0 }}', {}),
        throwsA(isA<TemplateRenderException>()),
      );
    });
  });

  group('malformed templates', () {
    for (final (src, line) in [
      ('{{ x', 1),
      ('\n{!! x', 2),
      ('@if(a)\n', 1),
      ('\n\n@foreach(a as)\n@endforeach', 3),
      ('@section("a")', 1),
      ('<x-a>', 1),
      ('\n<x-a foo=bar />', 2),
      ('@include()', 1),
      ('{{ a b }}', 1),
      ('@if(a)@else@else@endif', 1),
    ]) {
      test(
        "'${src.replaceAll('\n', r'\n')}' is a syntax error at line $line",
        () {
          expect(
            () => Khnum.inMemory({'t': src}).renderSync('t'),
            throwsA(
              isA<TemplateSyntaxException>()
                  .having((e) => e.template, 'template', 't')
                  .having((e) => e.line, 'line', line),
            ),
          );
        },
      );
    }
  });
}

class _Evil {
  @override
  String toString() => '<b>';
}
