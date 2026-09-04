import 'exceptions.dart';

enum TokenKind {
  text,
  echo,
  rawEcho,
  directive,
  componentOpen,
  componentClose,
  slotOpen,
  slotClose,
}

class RawAttribute {
  const RawAttribute(this.name, this.value, {required this.bound});
  final String name;

  /// `null` for a bare attribute (`disabled`).
  final String? value;
  final bool bound;
}

class Token {
  Token(
    this.kind,
    this.line, {
    this.text = '',
    this.args,
    this.attributes = const [],
    this.selfClosing = false,
  });

  final TokenKind kind;
  final int line;

  /// Text content, expression source, directive name, or component name.
  final String text;

  /// Raw text between the parentheses of a directive, `null` when absent.
  final String? args;
  final List<RawAttribute> attributes;
  final bool selfClosing;

  @override
  String toString() => '$kind($text)@$line';
}

final _identifier = RegExp(r'[A-Za-z_][A-Za-z0-9_]*');
final _componentName = RegExp(r'x-([A-Za-z0-9_][A-Za-z0-9_.\-]*)');
final _slotName = RegExp(r'x-slot(?::([A-Za-z0-9_\-]+))?');
final _attrStart = RegExp(r'(:?)([A-Za-z_][A-Za-z0-9_\-.:]*)');

/// Splits template source into tokens. Only names that
/// [isDirective] accepts become directives; any other `@word` stays text,
/// which keeps CSS `@media` and email addresses intact.
class Lexer {
  Lexer(this.source, this.template, this.isDirective, {int startLine = 1})
    : _line = startLine;

  final String source;
  final String template;
  final bool Function(String name) isDirective;

  int _pos = 0;
  int _line;
  final _tokens = <Token>[];
  final _text = StringBuffer();
  int _textLine = 1;

  TemplateSyntaxException _error(String message, [int? line]) =>
      TemplateSyntaxException(message, template: template, line: line ?? _line);

  List<Token> tokenize() {
    _textLine = _line;
    while (_pos < source.length) {
      if (_startsWith('{{--')) {
        _skipUntil('--}}', 'comment');
      } else if (_startsWith('@{{')) {
        _pos++;
        _emitText('{{');
        _pos += 2;
      } else if (_startsWith('@@')) {
        _emitText('@');
        _pos += 2;
      } else if (_startsWith('{!!')) {
        _echo('{!!', '!!}', TokenKind.rawEcho);
      } else if (_startsWith('{{')) {
        _echo('{{', '}}', TokenKind.echo);
      } else if (_startsWith('@') && _directive()) {
        // handled
      } else if (_startsWith('<x-') && _component()) {
        // handled
      } else if (_startsWith('</x-') && _componentClose()) {
        // handled
      } else {
        _emitText(source[_pos]);
        _pos++;
      }
    }
    _flushText();
    return _tokens;
  }

  bool _startsWith(String s) => source.startsWith(s, _pos);

  void _emitText(String s) {
    if (_text.isEmpty) _textLine = _line;
    _text.write(s);
    _line += '\n'.allMatches(s).length;
  }

  void _flushText() {
    if (_text.isEmpty) return;
    _tokens.add(Token(TokenKind.text, _textLine, text: _text.toString()));
    _text.clear();
  }

  void _add(Token token) {
    _flushText();
    _tokens.add(token);
  }

  /// A control directive alone on its line should not leave an empty HTML
  /// line behind. Echoes keep their following newline because they emit text.
  int _swallowNewline(int cursor) {
    if (source.startsWith('\r\n', cursor)) return cursor + 2;
    if (source.startsWith('\n', cursor)) return cursor + 1;
    return cursor;
  }

  void _skipUntil(String close, String what) {
    final start = _line;
    final end = source.indexOf(close, _pos);
    if (end < 0) throw _error('Unclosed $what', start);
    _line += '\n'.allMatches(source.substring(_pos, end)).length;
    _pos = end + close.length;
  }

  void _echo(String open, String close, TokenKind kind) {
    final start = _line;
    final end = source.indexOf(close, _pos + open.length);
    if (end < 0) throw _error("Unclosed '$open'", start);
    final expr = source.substring(_pos + open.length, end);
    _add(Token(kind, start, text: expr));
    _line += '\n'.allMatches(expr).length;
    _pos = end + close.length;
  }

  bool _directive() {
    final match = _identifier.matchAsPrefix(source, _pos + 1);
    if (match == null || !isDirective(match[0]!)) return false;
    final name = match[0]!;
    final start = _line;
    var cursor = match.end;
    // Allow `@if (cond)` with spaces before the parenthesis, but only
    // consume them when a parenthesis actually follows (`@else text`).
    var paren = cursor;
    while (paren < source.length && source[paren] == ' ') {
      paren++;
    }
    String? args;
    if (paren < source.length && source[paren] == '(') {
      final end = _matchingParen(paren);
      args = source.substring(paren + 1, end);
      cursor = end + 1;
    }
    _add(Token(TokenKind.directive, start, text: name, args: args));
    cursor = _swallowNewline(cursor);
    _line += '\n'.allMatches(source.substring(_pos, cursor)).length;
    _pos = cursor;
    return true;
  }

  /// Index of the `)` balancing the `(` at [open], skipping quoted strings.
  int _matchingParen(int open) {
    var depth = 0;
    var i = open;
    while (i < source.length) {
      final c = source[i];
      if (c == '"' || c == "'") {
        i = _skipString(i);
        continue;
      }
      if (c == '(') depth++;
      if (c == ')' && --depth == 0) return i;
      i++;
    }
    throw _error("Unclosed '(' in directive");
  }

  int _skipString(int start) {
    final quote = source[start];
    var i = start + 1;
    while (i < source.length && source[i] != quote) {
      if (source[i] == '\\') i++;
      i++;
    }
    return i + 1;
  }

  bool _component() {
    final slot = _slotName.matchAsPrefix(source, _pos + 1);
    final match = _componentName.matchAsPrefix(source, _pos + 1);
    if (slot == null && match == null) return false;
    final start = _line;
    final isSlot = slot != null && (match == null || slot.end >= match.end);
    var cursor = (isSlot ? slot : match!).end;
    final attributes = <RawAttribute>[];
    var selfClosing = false;
    while (true) {
      while (cursor < source.length && source[cursor].trim().isEmpty) {
        cursor++;
      }
      if (cursor >= source.length) {
        throw _error('Unclosed component tag', start);
      }
      if (source.startsWith('/>', cursor)) {
        selfClosing = true;
        cursor += 2;
        break;
      }
      if (source[cursor] == '>') {
        cursor++;
        break;
      }
      final attr = _attrStart.matchAsPrefix(source, cursor);
      if (attr == null) {
        throw _error("Unexpected '${source[cursor]}' in component tag", start);
      }
      cursor = attr.end;
      String? value;
      if (cursor < source.length && source[cursor] == '=') {
        cursor++;
        final quote = cursor < source.length ? source[cursor] : '';
        if (quote != '"' && quote != "'") {
          throw _error('Component attribute values must be quoted', start);
        }
        final end = source.indexOf(quote, cursor + 1);
        if (end < 0) throw _error('Unclosed attribute value', start);
        value = source.substring(cursor + 1, end);
        cursor = end + 1;
      }
      attributes.add(RawAttribute(attr[2]!, value, bound: attr[1] == ':'));
    }
    if (isSlot) {
      var name = slot[1];
      final named = attributes.where((a) => a.name == 'name').firstOrNull;
      name ??= named?.value;
      if (name == null) throw _error('<x-slot> needs a name', start);
      _add(Token(TokenKind.slotOpen, start, text: name));
    } else {
      _add(
        Token(
          TokenKind.componentOpen,
          start,
          text: match![1]!,
          attributes: attributes,
          selfClosing: selfClosing,
        ),
      );
    }
    cursor = _swallowNewline(cursor);
    _line += '\n'.allMatches(source.substring(_pos, cursor)).length;
    _pos = cursor;
    return true;
  }

  bool _componentClose() {
    final slot = _slotName.matchAsPrefix(source, _pos + 2);
    final match = _componentName.matchAsPrefix(source, _pos + 2);
    if (slot == null && match == null) return false;
    final isSlot = slot != null && (match == null || slot.end >= match.end);
    final m = isSlot ? slot : match!;
    var cursor = m.end;
    while (cursor < source.length && source[cursor].trim().isEmpty) {
      cursor++;
    }
    if (cursor >= source.length || source[cursor] != '>') {
      throw _error('Malformed closing tag');
    }
    _add(
      Token(
        isSlot ? TokenKind.slotClose : TokenKind.componentClose,
        _line,
        text: isSlot ? (slot[1] ?? '') : match![1]!,
      ),
    );
    cursor = _swallowNewline(cursor + 1);
    _line += '\n'.allMatches(source.substring(_pos, cursor)).length;
    _pos = cursor;
    return true;
  }
}
