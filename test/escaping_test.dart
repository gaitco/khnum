import 'package:khnum/khnum.dart';
import 'package:test/test.dart';

void main() {
  String render(String src, [Map<String, Object?> data = const {}]) =>
      Khnum.inMemory({'t': src}).renderSync('t', data);

  group('escapeHtml()', () {
    test('escapes the five HTML metacharacters', () {
      expect(
        escapeHtml('<a href="x">&\'</a>'),
        '&lt;a href=&quot;x&quot;&gt;&amp;&#39;&lt;/a&gt;',
      );
    });
    test('null is empty', () => expect(escapeHtml(null), ''));
    test('numbers and booleans stringify', () {
      expect(escapeHtml(1.5), '1.5');
      expect(escapeHtml(true), 'true');
    });
    test('HtmlString passes through', () {
      expect(escapeHtml(const HtmlString('<b>')), '<b>');
    });
  });

  group('{{ }}', () {
    test('escapes by default', () {
      expect(
        render('{{ v }}', {'v': '<script>alert("x")</script>'}),
        '&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;',
      );
    });
    test('escapes apostrophes and ampersands', () {
      expect(
        render('{{ v }}', {'v': "Tom & Jerry's"}),
        'Tom &amp; Jerry&#39;s',
      );
    });
    test('null renders as empty string', () {
      expect(render('[{{ v }}]', {'v': null}), '[]');
    });
    test('is safe inside attributes', () {
      expect(
        render('<a title="{{ v }}">', {'v': '" onclick="x'}),
        '<a title="&quot; onclick=&quot;x">',
      );
    });
    test('escapes toString of arbitrary objects', () {
      expect(
        render('{{ v }}', {'v': Uri.parse('http://x/?a=<b>')}),
        'http://x/?a=%3Cb%3E',
      );
    });
  });

  group('{!! !!}', () {
    test('outputs raw HTML', () {
      expect(render('{!! v !!}', {'v': '<b>x</b>'}), '<b>x</b>');
    });
    test('null renders as empty string', () {
      expect(render('[{!! v !!}]', {'v': null}), '[]');
    });
  });

  group('HtmlString', () {
    test('is not escaped by {{ }}', () {
      expect(
        render('{{ v }}', {'v': const HtmlString('<i>x</i>')}),
        '<i>x</i>',
      );
    });
  });

  group('json()', () {
    test('escapes < > & for use inside <script>', () {
      final out = render('{{ json(v) }}', {
        'v': {'x': '</script><b>&'},
      });
      expect(out, r'{"x":"\u003c/script\u003e\u003cb\u003e\u0026"}');
      expect(out, isNot(contains('<')));
    });
  });

  group('literal escapes', () {
    test('@{{ }} stays literal for client-side frameworks', () {
      expect(render('@{{ message }}'), '{{ message }}');
    });
    test('@@ is a literal @', () {
      expect(render('@@if'), '@if');
    });
    test('unknown @words are text', () {
      expect(
        render('@media (x) {} me@example.com'),
        '@media (x) {} me@example.com',
      );
    });
    test('{{-- --}} comments are dropped', () {
      expect(render('a{{-- hidden {{ x }} --}}b'), 'ab');
    });
  });
}
