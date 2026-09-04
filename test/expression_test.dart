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
    engine.function('double', (args) => (args.first as num) * 2);
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
      expect(eval('order["customer"].email', vars), 'a@b.c');
      expect(eval('point.y', vars), 4);
      expect(eval('items[1]', vars), 2);
      expect(eval('items.length', vars), 3);
      expect(eval('order["customer"].email', vars), 'a@b.c');
    });
    test('null access is explicit', () {
      expect(eval('user?.email', {'user': null}), null);
      expect(eval('items?[0]', {'items': null}), null);
      expect(eval('user?["profile"].name', {'user': null}), null);
      expect(
        () => eval('user?["profile"].name', {
          'user': {'profile': null},
        }),
        throwsA(isA<TemplateRenderException>()),
      );
      expect(
        () => eval('(user?["profile"]).name', {'user': null}),
        throwsA(isA<TemplateRenderException>()),
      );
      expect(eval('user!.email', {'user': Customer('a@b.c')}), 'a@b.c');
      expect(
        () => eval('user.email', {'user': null}),
        throwsA(isA<TemplateRenderException>()),
      );
      expect(
        () => eval('user!', {'user': null}),
        throwsA(isA<TemplateRenderException>()),
      );
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
        () => eval('user["nope"]', {'user': <String, Object?>{}}),
        throwsA(isA<UndefinedVariableException>()),
      );
    });
    test('maps use Dart properties and bracket keys', () {
      final map = {'name': 'Ann', 'entries': 'key value'};
      expect(eval('m.length', {'m': map}), 2);
      expect(eval('m["name"]', {'m': map}), 'Ann');
      expect(eval('m["entries"]', {'m': map}), 'key value');
      expect(eval('m.entries.length', {'m': map}), 2);
      expect(eval('m.entries.first.key', {'m': map}), 'name');
      expect(
        () => eval('m.name', {'m': map}),
        throwsA(isA<TemplateRenderException>()),
      );
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
    test('boolean operators reject non-booleans and still short-circuit', () {
      expect(eval('true && false'), false);
      expect(eval('false && missing'), false);
      expect(eval('true || missing'), true);
      for (final source in ['true && 0', '"" || true', '!null']) {
        expect(
          () => eval(source),
          throwsA(isA<TemplateRenderException>()),
          reason: source,
        );
      }
    });
    test('arithmetic and concatenation', () {
      expect(eval('1 + 2 * 3'), 7);
      expect(eval('(1 + 2) * 3'), 9);
      expect(eval('10 / 4'), 2.5);
      expect(eval('7 % 3'), 1);
      expect(eval('-x', {'x': 2}), -2);
    });
    test('string addition does not coerce other values', () {
      expect(eval('"a" + "b"'), 'ab');
      expect(() => eval('"a" + 1'), throwsA(isA<TemplateRenderException>()));
    });
    test('null coalescing and ternary', () {
      expect(eval('null ?? "d"'), 'd');
      expect(eval('x ?? "d"', {'x': 0}), 0);
      expect(eval('true ? "y" : "n"'), 'y');
      expect(eval('false ? "y" : "n"'), 'n');
    });
    test('coalescing does not hide missing names', () {
      expect(eval('nickname ?? "anonymous"', {'nickname': null}), 'anonymous');
      expect(
        () => eval('missing ?? "anonymous"'),
        throwsA(isA<UndefinedVariableException>()),
      );
    });
    test('ternary conditions require bool', () {
      expect(
        () => eval('0 ? "y" : "n"'),
        throwsA(isA<TemplateRenderException>()),
      );
    });
    test('type errors are render exceptions', () {
      expect(() => eval('1 - "a"'), throwsA(isA<TemplateRenderException>()));
      expect(() => eval('1 < "a"'), throwsA(isA<TemplateRenderException>()));
    });
  });

  group('calls', () {
    test('registered Dart functions are callable', () {
      engine.function('triple', (arguments) => (arguments.first as num) * 3);
      expect(eval('triple(4)'), 12);
    });
    test('registered functions', () {
      expect(eval('double(4)'), 8);
      expect(eval('upper("a")'), 'A');
      expect(eval('count([1, 2])'), 2);
    });
    test('unknown function is a render error', () {
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
