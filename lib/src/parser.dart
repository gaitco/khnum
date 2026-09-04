import 'ast.dart';
import 'exceptions.dart';
import 'expression.dart';
import 'lexer.dart';

final _forArgs = RegExp(
  r'^\s*final\s+([A-Za-z_]\w*)\s+in\s+(.+?)\s*$',
  dotAll: true,
);

/// Directive names the parser understands. Everything else that is
/// registered on the engine is a custom [DirectiveNode].
const builtInDirectives = {
  'if',
  'elseif',
  'else',
  'endif',
  'for',
  'endfor',
  'section',
  'endsection',
  'stop',
  'show',
  'yield',
  'parent',
  'extends',
  'include',
  'props',
};

const removedDirectives = {'unless', 'endunless', 'foreach', 'endforeach'};

class _Body {
  _Body(this.nodes, this.slots, this.end);
  final List<Node> nodes;
  final Map<String, List<Node>> slots;
  final Token? end;
}

/// Turns a token stream into a [Template].
class Parser {
  Parser(this.tokens, this.template, {required this.isDirective});

  final List<Token> tokens;
  final String template;
  final bool Function(String) isDirective;

  int _pos = 0;
  Expression? _extends;

  static Template parseSource(
    String source,
    String template, {
    required bool Function(String) isDirective,
  }) {
    final tokens = Lexer(source, template, isDirective).tokenize();
    return Parser(tokens, template, isDirective: isDirective).parse();
  }

  Template parse() {
    final body = _body();
    return Template(template, body.nodes, extendsView: _extends);
  }

  TemplateSyntaxException _error(String message, Token at) =>
      TemplateSyntaxException(message, template: template, line: at.line);

  Expression _expr(Token t) {
    if (t.args == null || t.args!.trim().isEmpty) {
      throw _error('@${t.text} needs an argument, e.g. @${t.text}(...)', t);
    }
    return Expression.parse(t.args!, template: template, line: t.line);
  }

  List<Expression> _args(Token t, {required int min, required int max}) {
    final args = Expression.parseArguments(
      t.args,
      template: template,
      line: t.line,
    );
    if (args.length < min || args.length > max) {
      final expected = min == max ? '$min' : '$min to $max';
      throw _error(
        '@${t.text} takes $expected argument(s), got ${args.length}',
        t,
      );
    }
    return args;
  }

  String _name(Token t, Expression e) {
    final name = e.stringLiteral;
    if (name == null) {
      throw _error("@${t.text} name must be a quoted string", t);
    }
    return name;
  }

  /// Parses nodes until one of [until] directives, a slot boundary, or the
  /// close tag of [component]. Top level: until end of input.
  _Body _body({Set<String> until = const {}, String? component}) {
    final nodes = <Node>[];
    final slots = <String, List<Node>>{};
    while (_pos < tokens.length) {
      final t = tokens[_pos++];
      switch (t.kind) {
        case TokenKind.text:
          nodes.add(TextNode(t.line, t.text));
        case TokenKind.echo:
        case TokenKind.rawEcho:
          nodes.add(
            EchoNode(
              t.line,
              Expression.parse(t.text, template: template, line: t.line),
              raw: t.kind == TokenKind.rawEcho,
            ),
          );
        case TokenKind.directive:
          if (until.contains(t.text)) return _Body(nodes, slots, t);
          nodes.addAll(_directive(t));
        case TokenKind.componentOpen:
          nodes.add(_component(t));
        case TokenKind.componentClose:
          if (component == null) throw _error('Unexpected </x-${t.text}>', t);
          if (t.text != component) {
            throw _error(
              'Expected </x-$component> but found </x-${t.text}>',
              t,
            );
          }
          return _Body(nodes, slots, t);
        case TokenKind.slotOpen:
          if (component == null) {
            throw _error('<x-slot> is only valid inside a component', t);
          }
          final slot = _body();
          if (slot.end?.kind != TokenKind.slotClose) {
            throw _error("Unclosed <x-slot name=\"${t.text}\">", t);
          }
          slots[t.text] = slot.nodes;
        case TokenKind.slotClose:
          return _Body(nodes, slots, t);
      }
    }
    return _Body(nodes, slots, null);
  }

  _Body _block(Token opener, Set<String> until) {
    final body = _body(until: until);
    if (body.end == null || body.end!.kind != TokenKind.directive) {
      throw _error(
        '@${opener.text} is never closed; expected '
        '${until.map((d) => '@$d').join(' or ')}',
        opener,
      );
    }
    return body;
  }

  List<Node> _directive(Token t) {
    switch (t.text) {
      case 'if':
        return [_if(t)];
      case 'for':
        final m = _forArgs.firstMatch(t.args ?? '');
        if (m == null) {
          throw _error('@for expects `final item in items`', t);
        }
        final body = _block(t, const {'endfor'});
        return [
          ForNode(
            t.line,
            Expression.parse(m[2]!, template: template, line: t.line),
            m[1]!,
            body.nodes,
          ),
        ];
      case 'foreach':
        throw _error(
          '@foreach was removed in 0.2.0; use '
          '`@for (final item in items) ... @endfor`',
          t,
        );
      case 'endforeach':
        throw _error('@endforeach was removed in 0.2.0; use @endfor', t);
      case 'unless':
        throw _error('@unless was removed in 0.2.0; use @if (!value)', t);
      case 'endunless':
        throw _error('@endunless was removed in 0.2.0; use @endif', t);
      case 'section':
        final args = _args(t, min: 1, max: 2);
        final name = _name(t, args[0]);
        if (args.length == 2) {
          return [
            SectionNode(t.line, name, [EchoNode(t.line, args[1], raw: false)]),
          ];
        }
        final body = _block(t, const {'endsection', 'stop', 'show'});
        return [
          SectionNode(
            t.line,
            name,
            body.nodes,
            yieldsImmediately: body.end!.text == 'show',
          ),
        ];
      case 'yield':
        final args = _args(t, min: 1, max: 2);
        return [YieldNode(t.line, _name(t, args[0]), args.elementAtOrNull(1))];
      case 'parent':
        return [ParentNode(t.line)];
      case 'extends':
        if (_extends != null) throw _error('@extends may only appear once', t);
        _extends = _args(t, min: 1, max: 1).first;
        return const [];
      case 'include':
        final args = _args(t, min: 1, max: 2);
        return [IncludeNode(t.line, args[0], args.elementAtOrNull(1))];
      case 'props':
        return [PropsNode(t.line, _args(t, min: 1, max: 1).first)];
      case 'elseif':
      case 'else':
      case 'endif':
      case 'endfor':
      case 'endsection':
      case 'stop':
      case 'show':
        throw _error('Unexpected @${t.text} with no open block', t);
    }
    return [
      DirectiveNode(
        t.line,
        t.text,
        Expression.parseArguments(t.args, template: template, line: t.line),
      ),
    ];
  }

  IfNode _if(Token opener) {
    const end = 'endif';
    var condition = _expr(opener);
    final branches = <IfBranch>[];
    List<Node>? elseBody;
    while (true) {
      final body = _block(opener, {'elseif', 'else', end});
      if (elseBody != null) {
        elseBody = body.nodes;
      } else {
        branches.add(IfBranch(condition, body.nodes));
      }
      final terminator = body.end!;
      if (terminator.text == end) break;
      if (elseBody != null) {
        throw _error('@${terminator.text} after @else', terminator);
      }
      if (terminator.text == 'else') {
        elseBody = const [];
      } else {
        condition = _expr(terminator);
      }
    }
    return IfNode(opener.line, branches, elseBody);
  }

  ComponentNode _component(Token t) {
    final attributes = [for (final a in t.attributes) _attribute(a, t.line)];
    if (t.selfClosing) {
      return ComponentNode(t.line, t.text, attributes, const [], const {});
    }
    final body = _body(component: t.text);
    if (body.end?.kind != TokenKind.componentClose) {
      throw _error('<x-${t.text}> is never closed; expected </x-${t.text}>', t);
    }
    return ComponentNode(t.line, t.text, attributes, body.nodes, body.slots);
  }

  ComponentAttribute _attribute(RawAttribute a, int line) {
    final value = a.value;
    if (value == null) return ComponentAttribute(a.name);
    if (a.bound) {
      return ComponentAttribute(
        a.name,
        value: Expression.parse(value, template: template, line: line),
      );
    }
    if (!value.contains('{{')) {
      return ComponentAttribute(
        a.name,
        value: Expression.parse(
          "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'",
          template: template,
          line: line,
        ),
      );
    }
    final tokens = Lexer(
      value,
      template,
      isDirective,
      startLine: line,
    ).tokenize();
    final parts = Parser(tokens, template, isDirective: isDirective)._body();
    return ComponentAttribute(a.name, parts: parts.nodes);
  }
}
