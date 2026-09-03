import 'context.dart';
import 'exceptions.dart';

/// Khnum-loose truthiness: `null`, `false`, `0`, `''` and empty collections
/// are false; everything else is true.
bool isTruthy(Object? value) {
  if (value == null || value == false) return false;
  if (value is num) return value != 0;
  if (value is String) return value.isNotEmpty;
  if (value is Iterable) return value.isNotEmpty;
  if (value is Map) return value.isNotEmpty;
  return true;
}

/// A parsed expression from `{{ }}`, `@if()`, `:attr=""` and friends.
///
/// Grammar, lowest to highest precedence:
/// `a ? b : c` · `??` · `||` · `&&` · `== !=` · `< <= > >=` · `+ -` ·
/// `* / %` · unary `! -` · postfix `.name`, `[expr]`, `helper(args)`.
abstract class Expression {
  const Expression(this.line);

  final int line;

  Object? eval(RenderContext ctx);

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

  /// `!expr`, used by `@unless`.
  static Expression negate(Expression expression) =>
      _Unary(expression.line, '!', expression);

  /// The value of a string literal, or `null` for anything else.
  String? get stringLiteral {
    final self = this;
    return self is _Literal && self.value is String
        ? self.value as String
        : null;
  }
}

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
  Object? eval(RenderContext ctx) => ctx.member(target.eval(ctx), key, line);
}

class _Index extends Expression {
  const _Index(super.line, this.target, this.key);
  final Expression target;
  final Expression key;
  @override
  Object? eval(RenderContext ctx) =>
      ctx.index(target.eval(ctx), key.eval(ctx), line);
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
  Object? eval(RenderContext ctx) => ctx.callMethod(target.eval(ctx), name, [
    for (final a in args) a.eval(ctx),
  ], line);
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
    if (op == '!') return !isTruthy(value);
    if (value is num) return -value;
    throw ctx.error('Cannot negate ${_describe(value)}', line);
  }
}

class _Ternary extends Expression {
  const _Ternary(super.line, this.condition, this.then, this.otherwise);
  final Expression condition, then, otherwise;
  @override
  Object? eval(RenderContext ctx) =>
      isTruthy(condition.eval(ctx)) ? then.eval(ctx) : otherwise.eval(ctx);
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
        return isTruthy(l) && isTruthy(right.eval(ctx));
      case '||':
        return isTruthy(l) || isTruthy(right.eval(ctx));
    }
    final r = right.eval(ctx);
    switch (op) {
      case '==':
        return l == r;
      case '!=':
        return l != r;
      case '+':
        if (l is String || r is String) return '${_str(l)}${_str(r)}';
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

  /// `a ?? b`: like PHP's `??`, a missing variable or key on the left is
  /// treated as `null` instead of an error, so `{{ user.nick ?? 'anon' }}`
  /// works in development too.
  Object? _coalesce(RenderContext ctx) {
    Object? l;
    try {
      l = left.eval(ctx);
    } on UndefinedVariableException {
      l = null;
    }
    return l ?? right.eval(ctx);
  }

  int _compare(RenderContext ctx, Object? l, Object? r) {
    if (l is num && r is num) return l.compareTo(r);
    if (l is String && r is String) return l.compareTo(r);
    throw ctx.error(
      "Operator '$op' cannot compare ${_describe(l)} and ${_describe(r)}",
      line,
    );
  }
}

String _str(Object? v) => v == null ? '' : v.toString();

String _describe(Object? v) => v == null ? 'null' : '${v.runtimeType} ($v)';

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
  '??', '&&', '||', '==', '!=', '<=', '>=', // two-char first
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
      if (_accept('.')) {
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
          return inner;
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
