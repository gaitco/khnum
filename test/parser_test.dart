import 'package:khnum/khnum.dart';
import 'package:khnum/src/lexer.dart';
import 'package:khnum/src/parser.dart';
import 'package:test/test.dart';

void main() {
  List<Token> lex(String src) =>
      Lexer(src, 't', builtInDirectives.contains).tokenize();
  Template parse(String src) =>
      Parser.parseSource(src, 't', isDirective: builtInDirectives.contains);

  group('lexer', () {
    test('tracks lines across text, echo and directives', () {
      final tokens = lex('a\n{{ b\n}}\n@if(x)\nc@endif');
      expect(tokens.map((t) => '${t.kind.name}@${t.line}'), [
        'text@1',
        'echo@2',
        'text@3',
        'directive@4',
        'text@5',
        'directive@5',
      ]);
    });
    test('directive args keep nested parens and quoted parens', () {
      final t = lex('@include("a", {"x": f(1, (2))})').single;
      expect(t.args, '"a", {"x": f(1, (2))}');
      expect(lex('@if(x == ")")').single.args, 'x == ")"');
    });
    test('unknown directive-looking words are text', () {
      expect(lex('@media(x)').single.kind, TokenKind.text);
    });
    test('component open tags with attributes', () {
      final t = lex(
        '<x-alert type="ok" :user="u" dismissible class=\'a b\' />',
      ).single;
      expect(t.kind, TokenKind.componentOpen);
      expect(t.text, 'alert');
      expect(t.selfClosing, true);
      expect(
        t.attributes.map((a) => '${a.bound ? ':' : ''}${a.name}=${a.value}'),
        ['type=ok', ':user=u', 'dismissible=null', 'class=a b'],
      );
    });
    test('component close and slots', () {
      final kinds = lex(
        '<x-card><x-slot name="f">x</x-slot><x-slot:g>y</x-slot:g></x-card>',
      ).map((t) => t.kind).toList();
      expect(kinds, [
        TokenKind.componentOpen,
        TokenKind.slotOpen,
        TokenKind.text,
        TokenKind.slotClose,
        TokenKind.slotOpen,
        TokenKind.text,
        TokenKind.slotClose,
        TokenKind.componentClose,
      ]);
    });
    test('dotted component names for subdirectories', () {
      expect(lex('<x-forms.input />').single.text, 'forms.input');
    });
    test('unclosed echo reports line', () {
      expect(
        () => lex('\n\n{{ x'),
        throwsA(
          isA<TemplateSyntaxException>().having((e) => e.line, 'line', 3),
        ),
      );
    });
    test('unclosed comment', () {
      expect(() => lex('{{-- x'), throwsA(isA<TemplateSyntaxException>()));
    });
    test('unclosed component tag', () {
      expect(
        () => lex('<x-a type="1"'),
        throwsA(isA<TemplateSyntaxException>()),
      );
    });
  });

  group('parser', () {
    test('builds nested block structure', () {
      final t = parse('@if(a)@for (final i in l){{ i }}@endfor@else x@endif');
      final ifNode = t.nodes.single as IfNode;
      expect(ifNode.branches.single.body.single, isA<ForNode>());
      expect((ifNode.elseBody!.single as TextNode).text, ' x');
    });
    test('records extends and sections', () {
      final t = parse('@extends("l")@section("a")x@endsection@section("b", 1)');
      expect(t.extendsView, isNotNull);
      expect(t.nodes.whereType<SectionNode>().map((s) => s.name), ['a', 'b']);
    });
    test('component with slots', () {
      final t = parse(
        '<x-card :a="1">body<x-slot name="f">F</x-slot></x-card>',
      );
      final c = t.nodes.single as ComponentNode;
      expect(c.attributes.single.name, 'a');
      expect((c.body.single as TextNode).text, 'body');
      expect(c.slots.keys, ['f']);
    });
    test('mismatched component close', () {
      expect(
        () => parse('<x-a></x-b>'),
        throwsA(isA<TemplateSyntaxException>()),
      );
    });
    test('slot outside component', () {
      expect(
        () => parse('<x-slot name="a">x</x-slot>'),
        throwsA(isA<TemplateSyntaxException>()),
      );
    });
    test('section name must be a string literal', () {
      expect(
        () => parse('@section(name)x@endsection'),
        throwsA(isA<TemplateSyntaxException>()),
      );
    });
    test('wrong arity', () {
      expect(() => parse('@yield()'), throwsA(isA<TemplateSyntaxException>()));
      expect(
        () => parse('@include("a", {}, 3)'),
        throwsA(isA<TemplateSyntaxException>()),
      );
    });
    test('expression errors carry the template line', () {
      expect(
        () => parse('\n\n\n{{ 1 + }}'),
        throwsA(
          isA<TemplateSyntaxException>().having((e) => e.line, 'line', 4),
        ),
      );
    });
  });
}
