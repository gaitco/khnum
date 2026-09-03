import 'package:khnum/khnum.dart';
import 'package:test/test.dart';

void main() {
  test('custom directive receives evaluated arguments', () {
    final khnum = Khnum.inMemory({'t': 'Total: @money(price, "EUR")'})
      ..directive('money', (ctx, args) {
        final amount = args[0] as num;
        return '${args[1]} ${amount.toStringAsFixed(2)}';
      });
    expect(khnum.renderSync('t', {'price': 9.5}), 'Total: EUR 9.50');
  });

  test('directive output is raw; escapeHtml is available', () {
    final khnum = Khnum.inMemory({'t': '@raw(v)|@safe(v)'})
      ..directive('raw', (ctx, args) => args.first)
      ..directive('safe', (ctx, args) => escapeHtml(args.first));
    expect(khnum.renderSync('t', {'v': '<b>'}), '<b>|&lt;b&gt;');
  });

  test('directive can read the render context', () {
    final khnum = Khnum.inMemory({'t': '@greet'})
      ..directive('greet', (ctx, args) => 'Hi ${ctx.lookup('name', 1)}');
    expect(khnum.renderSync('t', {'name': 'Ann'}), 'Hi Ann');
  });

  test('unregistered words stay text; registering clears the cache', () {
    final khnum = Khnum.inMemory({
      't': '@money(1)',
    }, environment: TemplateEnvironment.production);
    expect(khnum.renderSync('t'), '@money(1)');
    khnum.directive('money', (ctx, args) => 'x');
    expect(khnum.renderSync('t'), 'x');
  });

  test('built-in names cannot be overridden', () {
    final khnum = Khnum.inMemory({});
    expect(() => khnum.directive('if', (c, a) => ''), throwsArgumentError);
  });

  test('exceptions inside a directive carry template and line', () {
    final khnum = Khnum.inMemory({'t': '\n\n@boom'})
      ..directive('boom', (ctx, args) => throw StateError('bad'));
    expect(
      () => khnum.renderSync('t'),
      throwsA(
        isA<TemplateRenderException>()
            .having((e) => e.line, 'line', 3)
            .having((e) => e.message, 'message', contains('bad')),
      ),
    );
  });

  test('helpers and resolvers', () {
    final khnum = Khnum.inMemory({'t': '{{ money(p) }} {{ d.year }}'})
      ..helper('money', (a) => '\$${(a.first as num).toStringAsFixed(2)}')
      ..resolve<DateTime>((d, key) => key == 'year' ? d.year : null);
    expect(khnum.renderSync('t', {'p': 3, 'd': DateTime(2026)}), '\$3.00 2026');
  });
}
