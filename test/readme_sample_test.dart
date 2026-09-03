import 'package:maat_khnum_core/maat_khnum_core.dart';
import 'package:test/test.dart';

void main() {
  test('README and docs samples render', () {
    final khnum =
        Khnum.inMemory({
          'layouts.app':
              '<title>@yield("title", "Home")</title>@yield("content")',
          'components.alert':
              '@props({"type": "info"})\n'
              '<div {{ attributes.merge({"class": "alert alert-" + type}) }} role="alert">{{ slot }}</div>',
          'dashboard': '''
@extends("layouts.app")

@section("title", title)

@section("content")
<h1>{{ heading }}</h1>

@if(user)
    <x-alert type="success">Welcome back, {{ user.name }}!</x-alert>
@else
    <p>Please log in.</p>
@endif

<ul>
@foreach(items as item)
    <li>{{ item.name }} {{ loop.last ? "" : "|" }}</li>
@endforeach
</ul>
@endsection
''',
          'docs':
              '{{ nickname ?? "anonymous" }} {{ items.length > 0 ? "In stock" : "Sold out" }} @include(partialName) {{ upper(user.name) }}',
          'p': 'P',
        })..resolve<DateTime>(
          (date, key) => switch (key) {
            'year' => date.year,
            'iso' => date.toIso8601String(),
            _ => null,
          },
        );
    khnum.directive('datetime', (context, args) {
      final date = args.first as DateTime;
      return escapeHtml(date.toIso8601String());
    });
    final html = khnum.renderSync('dashboard', {
      'title': 'Dash',
      'heading': 'Hello',
      'user': {'name': 'Ann'},
      'items': [
        {'name': 'a'},
        {'name': 'b'},
      ],
    });
    expect(
      html,
      '<title>Dash</title><h1>Hello</h1>\n\n'
      '    <div class="alert alert-success" role="alert">Welcome back, Ann!</div>\n'
      '<ul>\n    <li>a |</li>\n    <li>b </li>\n</ul>\n',
    );
    expect(
      khnum.renderSync('docs', {
        'nickname': null,
        'items': [1],
        'partialName': 'p',
        'user': {'name': 'x'},
      }),
      'anonymous In stock P X',
    );
    final b2 = Khnum.inMemory({'d': '{{ d.year }} @datetime(d)'})
      ..resolve<DateTime>((date, key) => key == 'year' ? date.year : null)
      ..directive(
        'datetime',
        (c, a) => escapeHtml((a.first as DateTime).toIso8601String()),
      );
    expect(
      b2.renderSync('d', {'d': DateTime.utc(2026)}),
      '2026 2026-01-01T00:00:00.000Z',
    );
  });
}
