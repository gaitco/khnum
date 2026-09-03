import 'package:khnum/khnum.dart';
import 'package:test/test.dart';

class Customer {
  Customer(this.email);
  final String email;
  Map<String, Object?> toJson() => {'email': email};
}

class Point {
  Point(this.x, this.y);
  final int x, y;
}

void main() {
  late Khnum engine;
  setUp(() {
    engine = Khnum.inMemory({});
    engine.resolve<Point>((p, key) => key == 'x' ? p.x : p.y);
    engine.helper('double', (args) => (args.first as num) * 2);
  });

  Object? eval(String src, [Map<String, Object?> vars = const {}]) {
    final ctx = RenderContext(engine, 'test', vars);
    return Expression.parse(src, template: 'test', line: 1).eval(ctx);
  }

  group('literals', () {
    test('strings, numbers, booleans, null', () {
      expect(eval("'a'"), 'a');
      expect(eval('"b\\"c"'), 'b"c');
      expect(eval('42'), 42);
      expect(eval('1.5'), 1.5);
      expect(eval('true'), true);
      expect(eval('false'), false);
      expect(eval('null'), null);
    });
    test('lists and maps', () {
      expect(eval('[1, "a", true]'), [1, 'a', true]);
      expect(eval('{"k": 1, v: 2}'), {'k': 1, 'v': 2});
      expect(eval('{}'), <String, Object?>{});
    });
  });

  group('lookup', () {
    test('variables and nested members', () {
      final vars = {
        'title': 'Hi',
        'order': {'customer': Customer('a@b.c')},
        'point': Point(3, 4),
        'items': [1, 2, 3],
      };
      expect(eval('title', vars), 'Hi');
      expect(eval('order.customer.email', vars), 'a@b.c');
      expect(eval('point.y', vars), 4);
      expect(eval('items[1]', vars), 2);
      expect(eval('items.length', vars), 3);
      expect(eval('order["customer"].email', vars), 'a@b.c');
    });
    test('member access on null yields null', () {
      expect(eval('user.name', {'user': null}), null);
    });
    test('undefined variable throws with template and line', () {
      expect(
        () => eval('missing'),
        throwsA(
          isA<UndefinedVariableException>()
              .having((e) => e.template, 'template', 'test')
              .having((e) => e.line, 'line', 1),
        ),
      );
    });
    test('undefined map key throws', () {
      expect(
        () => eval('user.nope', {'user': <String, Object?>{}}),
        throwsA(isA<UndefinedVariableException>()),
      );
    });
    test('treatAsNull policy', () {
      engine = Khnum.inMemory(
        {},
        missingVariables: MissingVariables.treatAsNull,
      );
      expect(eval('missing'), null);
      expect(eval('missing.deeper'), null);
    });
    test('unresolvable object member is an error', () {
      expect(
        () => eval('o.x', {'o': Object()}),
        throwsA(isA<TemplateRenderException>()),
      );
    });
  });

  group('operators', () {
    test('comparison and equality', () {
      expect(eval('1 < 2'), true);
      expect(eval('2 <= 2'), true);
      expect(eval('3 > 4'), false);
      expect(eval('"a" == "a"'), true);
      expect(eval('1 != 1'), false);
      expect(eval('"b" > "a"'), true);
    });
    test('logic with loose truthiness and short-circuit', () {
      expect(eval('true && 0'), false);
      expect(eval('"" || "x"'), true);
      expect(eval('!null'), true);
      expect(eval('![]'), true);
      expect(eval('!{"a": 1}'), false);
      expect(eval('false && missing'), false);
      expect(eval('true || missing'), true);
    });
    test('arithmetic and concatenation', () {
      expect(eval('1 + 2 * 3'), 7);
      expect(eval('(1 + 2) * 3'), 9);
      expect(eval('10 / 4'), 2.5);
      expect(eval('7 % 3'), 1);
      expect(eval('-x', {'x': 2}), -2);
      expect(eval('"a" + 1'), 'a1');
    });
    test('null coalescing and ternary', () {
      expect(eval('null ?? "d"'), 'd');
      expect(eval('x ?? "d"', {'x': 0}), 0);
      expect(eval('true ? "y" : "n"'), 'y');
      expect(eval('0 ? "y" : "n"'), 'n');
    });
    test('type errors are render exceptions', () {
      expect(() => eval('1 - "a"'), throwsA(isA<TemplateRenderException>()));
      expect(() => eval('1 < "a"'), throwsA(isA<TemplateRenderException>()));
    });
  });

  group('calls', () {
    test('registered helpers', () {
      expect(eval('double(4)'), 8);
      expect(eval('upper("a")'), 'A');
      expect(eval('count([1, 2])'), 2);
    });
    test('unknown helper is a render error', () {
      expect(() => eval('nope(1)'), throwsA(isA<TemplateRenderException>()));
    });
    test('methods on values are not callable', () {
      expect(
        () => eval('s.toUpperCase()', {'s': 'a'}),
        throwsA(isA<TemplateRenderException>()),
      );
    });
  });

  group('syntax errors', () {
    for (final bad in ['1 +', '(1', '[1,', 'a.', '"unterminated', '1 === 1']) {
      test('"$bad" reports line', () {
        expect(
          () => Expression.parse(bad, template: 't', line: 7),
          throwsA(
            isA<TemplateSyntaxException>().having((e) => e.line, 'line', 7),
          ),
        );
      });
    }
  });
}
