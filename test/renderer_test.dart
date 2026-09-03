import 'dart:io';

import 'package:maat_khnum_core/maat_khnum_core.dart';
import 'package:test/test.dart';

class User {
  User(this.name);
  final String name;
  Map<String, Object?> toJson() => {'name': name};
}

void main() {
  test('the README example renders end to end', () {
    final khnum = Khnum.inMemory({
      'layouts.app':
          '<title>@yield("title")</title>\n<body>@yield("content")</body>',
      'dashboard': '''
@extends("layouts.app")

@section("title")
{{ title }}
@endsection

@section("content")
<h1>{{ heading }}</h1>

@if(showWelcome)
    <p>Welcome, {{ user.name }}!</p>
@else
    <p>Please log in.</p>
@endif

<ul>
@foreach(items as item)
    <li>{{ item.name }}</li>
@endforeach
</ul>
@endsection
''',
    });
    final html = khnum.renderSync('dashboard', {
      'title': 'Dash',
      'heading': 'Hello <world>',
      'showWelcome': true,
      'user': User('Ann'),
      'items': [
        User('a'),
        {'name': 'b'},
      ],
    });
    // Khnum-exact whitespace: a directive alone on its line leaves no blank
    // line; an echo keeps its trailing newline.
    expect(html, '''
<title>Dash
</title>
<body><h1>Hello &lt;world&gt;</h1>

    <p>Welcome, Ann!</p>

<ul>
    <li>a</li>
    <li>b</li>
</ul>
</body>''');
  });

  test('render() is the async form of renderSync()', () async {
    final khnum = Khnum.inMemory({'t': '{{ x }}'});
    expect(await khnum.render('t', {'x': 1}), '1');
  });

  test('shared variables reach every template and component', () {
    final khnum = Khnum.inMemory({
      't': '{{ app }}<x-c />',
      'components.c': '{{ app }}',
    })..share('app', 'App');
    expect(khnum.renderSync('t'), 'AppApp');
  });

  test('missing variable policy', () {
    final strict = Khnum.inMemory({'t': '{{ nope }}'});
    expect(
      () => strict.renderSync('t'),
      throwsA(isA<UndefinedVariableException>()),
    );
    final lax = Khnum.inMemory({
      't': '[{{ nope }}]',
    }, missingVariables: MissingVariables.treatAsNull);
    expect(lax.renderSync('t'), '[]');
  });

  test('exists()', () {
    final khnum = Khnum.inMemory({'t': ''});
    expect(khnum.exists('t'), true);
    expect(khnum.exists('nope'), false);
    expect(khnum.exists('../etc'), false);
  });

  group('file loader', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('khnum'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('loads nested views and reloads in development', () async {
      final file = File('${dir.path}/pages/home.khnum.html')
        ..createSync(recursive: true)
        ..writeAsStringSync('v1');
      final khnum = Khnum(viewsPath: dir.path);
      expect(khnum.renderSync('pages.home'), 'v1');
      // Ensure a distinct mtime on coarse filesystems.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      file.writeAsStringSync('v2');
      expect(khnum.renderSync('pages.home'), 'v2');
    });

    test('production keeps the first parse', () async {
      final file = File('${dir.path}/home.khnum.html')..writeAsStringSync('v1');
      final khnum = Khnum(
        viewsPath: dir.path,
        environment: TemplateEnvironment.production,
      );
      expect(khnum.renderSync('home'), 'v1');
      file.writeAsStringSync('v2');
      expect(khnum.renderSync('home'), 'v1');
      file.deleteSync();
      expect(khnum.renderSync('home'), 'v1');
    });

    test('custom extension and components path', () {
      File('${dir.path}/v/home.html')
        ..createSync(recursive: true)
        ..writeAsStringSync('<x-btn>go</x-btn>');
      File('${dir.path}/c/btn.html')
        ..createSync(recursive: true)
        ..writeAsStringSync('<button>{{ slot }}</button>');
      final khnum = Khnum(
        viewsPath: '${dir.path}/v',
        componentsPath: '${dir.path}/c',
        extension: '.html',
      );
      expect(khnum.renderSync('home'), '<button>go</button>');
    });

    test('missing file', () {
      final khnum = Khnum(viewsPath: dir.path);
      expect(
        () => khnum.renderSync('nope'),
        throwsA(isA<TemplateNotFoundException>()),
      );
    });
  });
}
