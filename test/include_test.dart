import 'package:khnum/khnum.dart';
import 'package:test/test.dart';

void main() {
  test('include shares the parent scope', () {
    final khnum = Khnum.inMemory({
      'page': '@include("partials.card")',
      'partials.card': '<div>{{ title }}</div>',
    });
    expect(khnum.renderSync('page', {'title': 'T'}), '<div>T</div>');
  });

  test('include with data overrides parent variables', () {
    final khnum = Khnum.inMemory({
      'page':
          '@for (final u in users)@include("card", {"user": u, "title": "x"})@endfor',
      'card': '{{ user["name"] }}:{{ title }};',
    });
    expect(
      khnum.renderSync('page', {
        'title': 'T',
        'users': [
          {'name': 'a'},
          {'name': 'b'},
        ],
      }),
      'a:x;b:x;',
    );
  });

  test('include data is a literal map with expressions', () {
    final khnum = Khnum.inMemory({
      'page': '@include("card", {"n": count(items) + 1})',
      'card': '{{ n }}',
    });
    expect(
      khnum.renderSync('page', {
        'items': [1, 2],
      }),
      '3',
    );
  });

  test('include with a dynamic view name', () {
    final khnum = Khnum.inMemory({'page': '@include(partial)', 'a': 'A'});
    expect(khnum.renderSync('page', {'partial': 'a'}), 'A');
  });

  test('slash separators are accepted', () {
    final khnum = Khnum.inMemory({
      'page': '@include("partials/card")',
      'partials.card': 'C',
    });
    expect(khnum.renderSync('page'), 'C');
  });

  test('missing include reports the including template and line', () {
    final khnum = Khnum.inMemory({'page': 'a\nb\n@include("nope")'});
    expect(
      () => khnum.renderSync('page'),
      throwsA(
        isA<TemplateNotFoundException>()
            .having((e) => e.template, 'template', 'page')
            .having((e) => e.line, 'line', 3)
            .having((e) => e.message, 'message', contains("'nope'")),
      ),
    );
  });

  test('errors inside an include name the included file', () {
    final khnum = Khnum.inMemory({
      'page': '@include("card")',
      'card': '\n\n{{ missing }}',
    });
    expect(
      () => khnum.renderSync('page'),
      throwsA(
        isA<UndefinedVariableException>()
            .having((e) => e.template, 'template', 'card')
            .having((e) => e.line, 'line', 3),
      ),
    );
  });

  test('an include may define a section for the layout', () {
    final khnum = Khnum.inMemory({
      'layout': '@yield("scripts")',
      'page': '@extends("layout")@include("widget")',
      'widget': '@section("scripts")<script></script>@endsection',
    });
    expect(khnum.renderSync('page'), '<script></script>');
  });

  test('non-map include data is an error', () {
    final khnum = Khnum.inMemory({'page': '@include("x", 1)', 'x': ''});
    expect(
      () => khnum.renderSync('page'),
      throwsA(isA<TemplateRenderException>()),
    );
  });
}
