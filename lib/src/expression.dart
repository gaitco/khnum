import 'context.dart';
import 'exceptions.dart';

/// A parsed expression from `{{ }}`, `@if()`, `:attr=""` and friends.
///
/// Grammar, lowest to highest precedence:
/// `a ? b : c` · `??` · `||` · `&&` · `== !=` · `< <= > >=` · `+ -` ·
/// `* / %` · unary `! -` · postfix `.name`, `[expr]`, `function(args)`.
abstract class Expression {
  const Expression(this.line);

  final int line;

  Object? eval(RenderContext ctx);

  Object? _evalPostfix(RenderContext ctx) => eval(ctx);

  static Expression parse(
    String source, {
    required String template,
    required int line,
  }) => _Parser(source, template, line).parse();

  /// Parses a comma-separated argument list such as the inside of
  /// `@include('view', {"a": 1})`. An empty or `null` source is no arguments.
  static List<Expression> parseArguments(
    String? source, {
    required String template,
    required int line,
  }) {
    if (source == null || source.trim().isEmpty) return const [];
    final list = _Parser('[$source]', template, line).parse() as _ListLiteral;
    return list.items;
  }

  /// The value of a string literal, or `null` for anything else.
  String? get stringLiteral {
    final self = this;
    return self is _Literal && self.value is String
        ? self.value as String
        : null;
  }
}

final class _NullShorted {
  const _NullShorted();
}

const _nullShorted = _NullShorted();

Object? _unwrapNullShort(Object? value) =>
    identical(value, _nullShorted) ? null : value;

class _Literal extends Expression {
  const _Literal(super.line, this.value);
  final Object? value;
  @override
  Object? eval(RenderContext ctx) => value;
}

class _Variable extends Expression {
  const _Variable(super.line, this.name);
  final String name;
  @override
  Object? eval(RenderContext ctx) => ctx.lookup(name, line);
}

class _Member extends Expression {
  const _Member(super.line, this.target, this.key);
  final Expression target;
  final String key;
  @override
  Object? eval(RenderContext ctx) => _unwrapNullShort(_evalPostfix(ctx));

  @override
  Object? _evalPostfix(RenderContext ctx) {
    final value = target._evalPostfix(ctx);
    return identical(value, _nullShorted)
        ? _nullShorted
        : ctx.member(value, key, line);
  }
}

class _Index extends Expression {
  const _Index(super.line, this.target, this.key);
  final Expression target;
  final Expression key;
  @override
  Object? eval(RenderContext ctx) => _unwrapNullShort(_evalPostfix(ctx));

  @override
  Object? _evalPostfix(RenderContext ctx) {
    final value = target._evalPostfix(ctx);
    return identical(value, _nullShorted)
        ? _nullShorted
        : ctx.index(value, key.eval(ctx), line);
  }
}

class _NullAwareMember extends Expression {
  const _NullAwareMember(super.line, this.target, this.key);
  final Expression target;
  final String key;

  @override
  Object? eval(RenderContext ctx) => _unwrapNullShort(_evalPostfix(ctx));

  @override
  Object? _evalPostfix(RenderContext ctx) {
    final value = target._evalPostfix(ctx);
    if (identical(value, _nullShorted) || value == null) return _nullShorted;
    return ctx.member(value, key, line);
  }
}

class _NullAwareIndex extends Expression {
  const _NullAwareIndex(super.line, this.target, this.key);
  final Expression target;
  final Expression key;

  @override
  Object? eval(RenderContext ctx) => _unwrapNullShort(_evalPostfix(ctx));

  @override
  Object? _evalPostfix(RenderContext ctx) {
    final value = target._evalPostfix(ctx);
    if (identical(value, _nullShorted) || value == null) return _nullShorted;
    return ctx.index(value, key.eval(ctx), line);
  }
}

class _NullAssert extends Expression {
  const _NullAssert(super.line, this.value);
  final Expression value;

  @override
  Object? eval(RenderContext ctx) => _unwrapNullShort(_evalPostfix(ctx));

  @override
  Object? _evalPostfix(RenderContext ctx) {
    final result = value._evalPostfix(ctx);
    if (identical(result, _nullShorted)) return _nullShorted;
    return result ??
        (throw ctx.error('Null check operator used on null', line));
  }
}

class _Call extends Expression {
  const _Call(super.line, this.name, this.args);
  final String name;
  final List<Expression> args;
  @override
  Object? eval(RenderContext ctx) =>
      ctx.call(name, [for (final a in args) a.eval(ctx)], line);
}

class _MethodCall extends Expression {
  const _MethodCall(super.line, this.target, this.name, this.args);
  final Expression target;
  final String name;
  final List<Expression> args;
  @override
  Object? eval(RenderContext ctx) => _unwrapNullShort(_evalPostfix(ctx));

  @override
  Object? _evalPostfix(RenderContext ctx) {
    final value = target._evalPostfix(ctx);
    if (identical(value, _nullShorted)) return _nullShorted;
    return ctx.callMethod(value, name, [
      for (final a in args) a.eval(ctx),
    ], line);
  }
}

class _Group extends Expression {
  const _Group(super.line, this.value);
  final Expression value;

  @override
  Object? eval(RenderContext ctx) => value.eval(ctx);
}

class _ListLiteral extends Expression {
  const _ListLiteral(super.line, this.items);
  final List<Expression> items;
  @override
  Object? eval(RenderContext ctx) => [for (final i in items) i.eval(ctx)];
}

class _MapLiteral extends Expression {
  const _MapLiteral(super.line, this.entries);
  final Map<String, Expression> entries;
  @override
  Object? eval(RenderContext ctx) => <String, Object?>{
    for (final e in entries.entries) e.key: e.value.eval(ctx),
  };
}

class _Unary extends Expression {
  const _Unary(super.line, this.op, this.operand);
  final String op;
  final Expression operand;
  @override
  Object? eval(RenderContext ctx) {
    final value = operand.eval(ctx);
    if (op == '!') return !_bool(ctx, value, line, "Operator '!'");
    if (value is num) return -value;
    throw ctx.error('Cannot negate ${_describe(value)}', line);
  }
}

class _Ternary extends Expression {
  const _Ternary(super.line, this.condition, this.then, this.otherwise);
  final Expression condition, then, otherwise;
  @override
  Object? eval(RenderContext ctx) =>
      _bool(ctx, condition.eval(ctx), line, 'Ternary condition')
      ? then.eval(ctx)
      : otherwise.eval(ctx);
}

class _Binary extends Expression {
  const _Binary(super.line, this.op, this.left, this.right);
  final String op;
  final Expression left, right;

  @override
  Object? eval(RenderContext ctx) {
    if (op == '??') return _coalesce(ctx);
    final l = left.eval(ctx);
    switch (op) {
      case '&&':
        if (!_bool(ctx, l, line, "Operator '&&'")) return false;
        return _bool(ctx, right.eval(ctx), line, "Operator '&&'");
      case '||':
        if (_bool(ctx, l, line, "Operator '||'")) return true;
        return _bool(ctx, right.eval(ctx), line, "Operator '||'");
    }
    final r = right.eval(ctx);
    switch (op) {
      case '==':
        return l == r;
      case '!=':
        return l != r;
      case '+':
        if (l is String && r is String) return '$l$r';
        return _num(ctx, l, r, (a, b) => a + b);
      case '-':
        return _num(ctx, l, r, (a, b) => a - b);
      case '*':
        return _num(ctx, l, r, (a, b) => a * b);
      case '/':
        return _num(ctx, l, r, (a, b) => a / b);
      case '%':
        return _num(ctx, l, r, (a, b) => a % b);
      case '<':
        return _compare(ctx, l, r) < 0;
      case '<=':
        return _compare(ctx, l, r) <= 0;
      case '>':
        return _compare(ctx, l, r) > 0;
      case '>=':
        return _compare(ctx, l, r) >= 0;
    }
    throw StateError('unreachable operator $op');
  }

  Object? _num(
    RenderContext ctx,
    Object? l,
    Object? r,
    num Function(num, num) apply,
  ) {
    if (l is num && r is num) return apply(l, r);
    throw ctx.error(
      "Operator '$op' needs numbers, got ${_describe(l)} and ${_describe(r)}",
      line,
    );
  }

  Object? _coalesce(RenderContext ctx) => left.eval(ctx) ?? right.eval(ctx);

  int _compare(RenderContext ctx, Object? l, Object? r) {
    if (l is num && r is num) return l.compareTo(r);
    if (l is String && r is String) return l.compareTo(r);
    throw ctx.error(
      "Operator '$op' cannot compare ${_describe(l)} and ${_describe(r)}",
      line,
    );
  }
}

String _describe(Object? v) => v == null ? 'null' : '${v.runtimeType} ($v)';

bool _bool(RenderContext ctx, Object? value, int line, String use) {
  if (value is bool) return value;
  throw ctx.error(
    '$use requires bool, got ${value == null ? 'null' : value.runtimeType}',
    line,
  );
}

// ---------------------------------------------------------------------------
// Lexer
// ---------------------------------------------------------------------------

enum _Kind { ident, number, string, op, eof }

class _Token {
  _Token(this.kind, this.text);
  final _Kind kind;
  final String text;
}

const _operators = [
  '?.', '?[', '??', '&&', '||', '==', '!=', '<=', '>=', // two-char first
  '<', '>', '+', '-', '*', '/', '%', '!', '?', ':', '.', ',',
  '(', ')', '[', ']', '{', '}',
];

class _Parser {
  _Parser(this.source, this.template, this.line) {
    _tokens = _lex();
  }

  final String source;
  final String template;
  final int line;
  late final List<_Token> _tokens;
  int _pos = 0;

  TemplateSyntaxException _error(String message) => TemplateSyntaxException(
    "$message in expression '${source.trim()}'",
    template: template,
    line: line,
  );

  List<_Token> _lex() {
    final tokens = <_Token>[];
    var i = 0;
    while (i < source.length) {
      final c = source[i];
      if (c.trim().isEmpty) {
        i++;
        continue;
      }
      if (_isIdentStart(c)) {
        final start = i;
        while (i < source.length && _isIdentPart(source[i])) {
          i++;
        }
        tokens.add(_Token(_Kind.ident, source.substring(start, i)));
        continue;
      }
      if (_isDigit(c)) {
        final start = i;
        while (i < source.length && _isDigit(source[i])) {
          i++;
        }
        if (i + 1 < source.length &&
            source[i] == '.' &&
            _isDigit(source[i + 1])) {
          i++;
          while (i < source.length && _isDigit(source[i])) {
            i++;
          }
        }
        tokens.add(_Token(_Kind.number, source.substring(start, i)));
        continue;
      }
      if (c == '"' || c == "'") {
        final buffer = StringBuffer();
        i++;
        var closed = false;
        while (i < source.length) {
          final ch = source[i];
          if (ch == '\\' && i + 1 < source.length) {
            final next = source[i + 1];
            buffer.write(switch (next) {
              'n' => '\n',
              't' => '\t',
              _ => next,
            });
            i += 2;
            continue;
          }
          if (ch == c) {
            closed = true;
            i++;
            break;
          }
          buffer.write(ch);
          i++;
        }
        if (!closed) throw _error('Unterminated string');
        tokens.add(_Token(_Kind.string, buffer.toString()));
        continue;
      }
      final op = _operators.firstWhere(
        (o) => source.startsWith(o, i),
        orElse: () => '',
      );
      if (op.isEmpty) throw _error("Unexpected character '$c'");
      tokens.add(_Token(_Kind.op, op));
      i += op.length;
    }
    tokens.add(_Token(_Kind.eof, ''));
    return tokens;
  }

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;
  static bool _isIdentStart(String c) => RegExp(r'[A-Za-z_$]').hasMatch(c);
  static bool _isIdentPart(String c) => RegExp(r'[A-Za-z0-9_$]').hasMatch(c);

  // -------------------------------------------------------------------------
  // Parser
  // -------------------------------------------------------------------------

  _Token get _peek => _tokens[_pos];
  _Token _next() => _tokens[_pos++];

  bool _isOp(String op) => _peek.kind == _Kind.op && _peek.text == op;

  bool _accept(String op) {
    if (!_isOp(op)) return false;
    _pos++;
    return true;
  }

  void _expect(String op) {
    if (!_accept(op)) {
      throw _error(
        "Expected '$op' but found ${_peek.kind == _Kind.eof ? 'end of expression' : "'${_peek.text}'"}",
      );
    }
  }

  Expression parse() {
    if (_peek.kind == _Kind.eof) throw _error('Empty expression');
    final expr = _ternary();
    if (_peek.kind != _Kind.eof) {
      throw _error("Unexpected '${_peek.text}'");
    }
    return expr;
  }

  Expression _ternary() {
    final condition = _binary(0);
    if (!_accept('?')) return condition;
    final then = _ternary();
    _expect(':');
    return _Ternary(line, condition, then, _ternary());
  }

  static const _precedence = {
    '??': 1,
    '||': 2,
    '&&': 3,
    '==': 4,
    '!=': 4,
    '<': 5,
    '<=': 5,
    '>': 5,
    '>=': 5,
    '+': 6,
    '-': 6,
    '*': 7,
    '/': 7,
    '%': 7,
  };

  Expression _binary(int minPrecedence) {
    var left = _unary();
    while (_peek.kind == _Kind.op) {
      final prec = _precedence[_peek.text];
      if (prec == null || prec < minPrecedence) break;
      final op = _next().text;
      left = _Binary(line, op, left, _binary(prec + 1));
    }
    return left;
  }

  Expression _unary() {
    if (_accept('!')) return _Unary(line, '!', _unary());
    if (_accept('-')) return _Unary(line, '-', _unary());
    return _postfix(_primary());
  }

  Expression _postfix(Expression target) {
    while (true) {
      if (_accept('?.')) {
        final name = _next();
        if (name.kind != _Kind.ident) {
          throw _error("Expected a property name after '?.'");
        }
        if (_isOp('(')) {
          throw _error('Null-aware method calls are not supported');
        }
        target = _NullAwareMember(line, target, name.text);
      } else if (_accept('?[')) {
        final key = _ternary();
        _expect(']');
        target = _NullAwareIndex(line, target, key);
      } else if (_accept('.')) {
        final name = _next();
        if (name.kind != _Kind.ident) {
          throw _error("Expected a property name after '.'");
        }
        if (_accept('(')) {
          target = _MethodCall(line, target, name.text, _arguments());
        } else {
          target = _Member(line, target, name.text);
        }
      } else if (_accept('[')) {
        final key = _ternary();
        _expect(']');
        target = _Index(line, target, key);
      } else if (_accept('!')) {
        target = _NullAssert(line, target);
      } else {
        return target;
      }
    }
  }

  List<Expression> _arguments() {
    final args = <Expression>[];
    if (_accept(')')) return args;
    do {
      args.add(_ternary());
    } while (_accept(','));
    _expect(')');
    return args;
  }

  Expression _primary() {
    final token = _next();
    switch (token.kind) {
      case _Kind.number:
        return _Literal(line, num.parse(token.text));
      case _Kind.string:
        return _Literal(line, token.text);
      case _Kind.ident:
        switch (token.text) {
          case 'true':
            return const _Literal(0, true);
          case 'false':
            return const _Literal(0, false);
          case 'null':
            return const _Literal(0, null);
        }
        if (_accept('(')) return _Call(line, token.text, _arguments());
        return _Variable(line, token.text);
      case _Kind.op:
        if (token.text == '(') {
          final inner = _ternary();
          _expect(')');
          return _Group(line, inner);
        }
        if (token.text == '[') {
          final items = <Expression>[];
          while (!_accept(']')) {
            items.add(_ternary());
            if (!_accept(',')) {
              _expect(']');
              break;
            }
          }
          return _ListLiteral(line, items);
        }
        if (token.text == '{') {
          final entries = <String, Expression>{};
          while (!_accept('}')) {
            final key = _next();
            if (key.kind != _Kind.ident && key.kind != _Kind.string) {
              throw _error('Expected a map key');
            }
            _expect(':');
            entries[key.text] = _ternary();
            if (!_accept(',')) {
              _expect('}');
              break;
            }
          }
          return _MapLiteral(line, entries);
        }
        throw _error("Unexpected '${token.text}'");
      case _Kind.eof:
        throw _error('Unexpected end of expression');
    }
  }
}
