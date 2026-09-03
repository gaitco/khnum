import 'package:maat_khnum_core/maat_khnum_core.dart';
import 'package:test/test.dart';

void main() {
  Khnum engine(Map<String, String> views) => Khnum.inMemory(views);

  test('slot and literal attributes', () {
    final khnum = engine({
      'page': '<x-alert type="success">Profile <b>updated</b>.</x-alert>',
      'components.alert': '<div class="alert-{{ type }}">{{ slot }}</div>',
    });
    expect(
      khnum.renderSync('page'),
      '<div class="alert-success">Profile <b>updated</b>.</div>',
    );
  });

  test('bound attributes evaluate in the caller scope', () {
    final khnum = engine({
      'page': '<x-user-card :user="user" :count="items.length" />',
      'components.user-card': '{{ user.name }} ({{ count }})',
    });
    expect(
      khnum.renderSync('page', {
        'user': {'name': 'Ann'},
        'items': [1, 2],
      }),
      'Ann (2)',
    );
  });

  test('components are isolated from the caller scope', () {
    final khnum = engine({'page': '<x-c />', 'components.c': '{{ secret }}'});
    expect(
      () => khnum.renderSync('page', {'secret': 'x'}),
      throwsA(
        isA<UndefinedVariableException>().having(
          (e) => e.template,
          'template',
          'components.c',
        ),
      ),
    );
  });

  test('interpolated attribute strings', () {
    final khnum = engine({
      'page': '<x-btn class="btn {{ size }}" />',
      'components.btn': '[{{ class }}]',
    });
    expect(khnum.renderSync('page', {'size': 'lg'}), '[btn lg]');
  });

  test('named slots via name attribute and shorthand', () {
    final khnum = engine({
      'page':
          '<x-card>'
          '<x-slot name="header">H</x-slot>'
          'body'
          '<x-slot:footer>F</x-slot:footer>'
          '</x-card>',
      'components.card': '{{ header }}|{{ slot }}|{{ footer }}',
    });
    expect(khnum.renderSync('page'), 'H|body|F');
  });

  test('@props gives defaults and keeps declared props out of attributes', () {
    final khnum = engine({
      'page': '<x-alert type="warn" id="a1" data-x="1" disabled />',
      'components.alert':
          '@props({"type": "info", "title": null})'
          '{{ type }}/{{ title }}/<div {{ attributes }}>',
    });
    expect(khnum.renderSync('page'), 'warn//<div id="a1" data-x="1" disabled>');
  });

  test('attributes bag escapes values and supports merge', () {
    final khnum = engine({
      'page': '<x-b class="x" title=\'"q"\' />',
      'components.b':
          '<b {{ attributes.merge({"class": "btn", "role": "button"}) }}>',
    });
    expect(
      khnum.renderSync('page'),
      '<b class="btn x" role="button" title="&quot;q&quot;">',
    );
  });

  test('nested and dotted component names', () {
    final khnum = engine({
      'page':
          '<x-forms.input name="email"><x-forms.label>Email</x-forms.label></x-forms.input>',
      'components.forms.input':
          '<label>{{ slot }}</label><input name="{{ name }}">',
      'components.forms.label': '<span>{{ slot }}</span>',
    });
    expect(
      khnum.renderSync('page'),
      '<label><span>Email</span></label><input name="email">',
    );
  });

  test('slot content is escaped once, at the echo that produced it', () {
    final khnum = engine({
      'page': '<x-c>{{ v }}</x-c>',
      'components.c': '[{{ slot }}]',
    });
    expect(khnum.renderSync('page', {'v': '<i>'}), '[&lt;i&gt;]');
  });

  test('a component may use the layout sections of the page', () {
    final khnum = engine({
      'layout': '@yield("content")|@yield("scripts")',
      'page': '@extends("layout")@section("content")<x-chart />@endsection',
      'components.chart':
          '<canvas></canvas>@section("scripts")<script></script>@endsection',
    });
    expect(khnum.renderSync('page'), '<canvas></canvas>|<script></script>');
  });

  test('missing component names the caller template and line', () {
    final khnum = engine({'page': '\n<x-nope />'});
    expect(
      () => khnum.renderSync('page'),
      throwsA(
        isA<TemplateNotFoundException>()
            .having((e) => e.template, 'template', 'page')
            .having((e) => e.line, 'line', 2)
            .having((e) => e.message, 'message', contains('components.nope')),
      ),
    );
  });

  test('loops inside slots', () {
    final khnum = engine({
      'page':
          '<x-list>@foreach(items as i)<li>{{ i }}</li>@endforeach</x-list>',
      'components.list': '<ul>{{ slot }}</ul>',
    });
    expect(
      khnum.renderSync('page', {
        'items': [1, 2],
      }),
      '<ul><li>1</li><li>2</li></ul>',
    );
  });
}
