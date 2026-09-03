import 'package:maat_khnum_core/maat_khnum_core.dart';
import 'package:test/test.dart';

void main() {
  const layout = '''
<!DOCTYPE html>
<title>@yield("title", "Default")</title>
@section("sidebar")
<aside>base</aside>
@show
<main>@yield("content")</main>''';

  test('child fills sections, defaults apply, whitespace is dropped', () {
    final khnum = Khnum.inMemory({
      'layouts.app': layout,
      'page': '''
@extends("layouts.app")

@section("content")
<h1>{{ heading }}</h1>
@endsection
''',
    });
    expect(khnum.renderSync('page', {'heading': 'Hi'}), '''
<!DOCTYPE html>
<title>Default</title>
<aside>base</aside>
<main><h1>Hi</h1>
</main>''');
  });

  test('inline section and title from a variable', () {
    final khnum = Khnum.inMemory({
      'layouts.app': layout,
      'page': '@extends("layouts.app")@section("title", title)',
    });
    expect(
      khnum.renderSync('page', {'title': 'A & B'}),
      contains('<title>A &amp; B</title>'),
    );
  });

  test('@parent appends to the layout section', () {
    final khnum = Khnum.inMemory({
      'layouts.app': layout,
      'page':
          '@extends("layouts.app")'
          '@section("sidebar")@parent<b>child</b>@endsection',
    });
    expect(
      khnum.renderSync('page'),
      contains('<aside>base</aside>\n<b>child</b>'),
    );
  });

  test('child section overrides layout @show section entirely', () {
    final khnum = Khnum.inMemory({
      'layouts.app': layout,
      'page': '@extends("layouts.app")@section("sidebar")only@stop',
    });
    final html = khnum.renderSync('page');
    expect(html, contains('only'));
    expect(html, isNot(contains('<aside>')));
  });

  test('three levels of inheritance', () {
    final khnum = Khnum.inMemory({
      'base': '[@yield("a")|@yield("b")]',
      'mid': '@extends("base")@section("a")mid-a@endsection',
      'leaf': '@extends("mid")@section("b")leaf-b@endsection',
    });
    expect(khnum.renderSync('leaf'), '[mid-a|leaf-b]');
  });

  test('sections see the child template variables', () {
    final khnum = Khnum.inMemory({
      'base': '@yield("a")',
      'leaf': '@extends("base")@section("a"){{ x }}@endsection',
    });
    expect(khnum.renderSync('leaf', {'x': 'v'}), 'v');
  });

  test('extends with a dynamic name', () {
    final khnum = Khnum.inMemory({
      'base': 'B@yield("a")',
      'leaf': '@extends(layoutName)@section("a")!@endsection',
    });
    expect(khnum.renderSync('leaf', {'layoutName': 'base'}), 'B!');
  });

  test('missing layout names the child template and line', () {
    final khnum = Khnum.inMemory({'leaf': '\n@extends("nope")'});
    expect(
      () => khnum.renderSync('leaf'),
      throwsA(
        isA<TemplateNotFoundException>()
            .having((e) => e.template, 'template', 'leaf')
            .having((e) => e.line, 'line', 2),
      ),
    );
  });

  test('yield default is escaped', () {
    final khnum = Khnum.inMemory({'t': '@yield("x", "<b>")'});
    expect(khnum.renderSync('t'), '&lt;b&gt;');
  });

  test('@extends twice is a syntax error', () {
    final khnum = Khnum.inMemory({'t': '@extends("a")@extends("b")'});
    expect(
      () => khnum.renderSync('t'),
      throwsA(isA<TemplateSyntaxException>()),
    );
  });
}
