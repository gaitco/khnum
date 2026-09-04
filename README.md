# Khnum Templates

<p align="center"><img src="assets/icon.svg" width="96" alt="Khnum icon"></p>

Khnum is an HTML template engine for pure Dart servers. It supports layouts,
includes, components, loops, and HTML escaping by default. It uses no Flutter,
code generation, or reflection and works with Shelf, Dart Frog, Serverpod, or
`dart:io`.

Khnum templates are HTML with a small presentation expression language. They
do not execute Dart source. Prepare data and perform I/O in normal Dart code,
then pass the result to the view; register a Dart function when several views
need the same formatting operation.

```dart
final khnum = Khnum(viewsPath: 'views')
  ..function(
    'money',
    (arguments) => '\$${(arguments.first as num).toStringAsFixed(2)}',
  );

final html = await khnum.render('dashboard', {
  'title': 'Dashboard',
  'user': user,
  'orders': orders,
});
```

```html
{{-- views/dashboard.khnum.html --}}
<h1>{{ title }}</h1>

@if (user != null)
  <p>Welcome, {{ user.name }}.</p>
@endif

@if (orders.isEmpty)
  <p>No orders yet.</p>
@else
  <ul>
  @for (final order in orders)
    <li>#{{ order["id"] }} — {{ money(order["total"]) }}</li>
  @endfor
  </ul>
@endif
```

Return the HTML from any Dart server. With Shelf:

```dart
return Response.ok(
  html,
  headers: {'content-type': 'text/html; charset=utf-8'},
);
```

A complete server is in `example/shelf_example.dart`:

```bash
PORT=8080 dart run example/shelf_example.dart
```

The Maat integration guide is at [`docs/views.md`](../../docs/views.md).

## Expressions follow Dart's intent

Conditions are booleans. Khnum does not coerce `null`, `0`, strings, or
collections to `false`:

```html
@if (items.isNotEmpty) ... @endif
@if (user != null) ... @endif
@if (!isGuest) ... @endif
```

Nullable access is explicit:

```html
{{ user?.name ?? "Guest" }}
{{ values?[0] }}
{{ requiredUser!.name }}
```

`??` handles an existing value that is `null`; misspelled variables and
missing keys always throw an error containing the template name and line.

Raw maps use brackets for keys. Dot access exposes collection properties:

```html
{{ userMap["name"] }}
{{ items.length }}
{{ items.first }}
{{ settings.keys }}

@for (final entry in settings.entries)
  {{ entry.key }}={{ entry.value }}
@endfor
```

Objects with `toJson()` expose their declared fields with dot access. For
other application types, register a property resolver:

```dart
khnum.resolve<DateTime>((date, property) => switch (property) {
  'year' => date.year,
  'iso' => date.toIso8601String(),
  _ => null,
});
```

The expression language supports literals, lists, maps, property and index
access, `+ - * / %`, comparisons, `&&`, `||`, `!`, `??`, `?:`, and registered
function calls. Arithmetic requires numbers; `+` joins strings only when both
operands are strings. Arbitrary instance method calls and Dart source execution
are intentionally unavailable.

## Templates

- `{{ expression }}` escapes HTML; `null` renders as an empty string.
- `{!! expression !!}` and `HtmlString` output trusted HTML without escaping.
- `{{-- comment --}}` is removed from output; `@{{` and `@@` escape template
  delimiters.
- `@if`, `@elseif`, `@else`, and `@endif` select branches.
- `@for (final item in items)` and `@endfor` iterate an `Iterable`.
- `loop` exposes `index`, `iteration`, `remaining`, `count`, `first`, `last`,
  `even`, `odd`, `depth`, and `parent`.
- `@extends`, `@section`, `@yield`, `@parent`, `@show`, and `@stop` compose
  layouts.
- `@include("view", {"key": value})` renders a partial with the parent scope.
- `<x-alert>`, bound attributes such as `:user="user"`, slots, `@props`, and
  `attributes.merge(...)` build anonymous components.

## Extending Khnum

Registered functions return values for expressions:

```dart
khnum.function('initials', (arguments) {
  final name = arguments.first as String;
  return name.split(' ').map((part) => part[0]).join();
});
```

Custom directives produce markup. Their return value is unescaped, so escape
user-controlled values with `escapeHtml` inside the handler:

```dart
khnum.directive(
  'badge',
  (context, arguments) => '<span>${escapeHtml(arguments.first)}</span>',
);
```

Use `share()` for application-wide values and a custom `TemplateLoader` when
templates do not live on the local filesystem. Production mode parses each
template once; development mode reloads a changed file.

## Safety boundary

View names are validated before filesystem access. Layouts, includes, and
components share a recursion limit. Escaped output is the default, and missing
data fails loudly.

Templates should still be trusted application files: although they cannot run
arbitrary Dart, they can read every value passed to them and perform expensive
loops.

## Migrating from `0.1.0`

| `0.1.0` | `0.2.0` |
|---|---|
| `@foreach(items as item)` | `@for (final item in items)` |
| `@endforeach` | `@endfor` |
| `@unless(value)` | `@if (!value)` |
| `@if(items)` | `@if (items.isNotEmpty)` |
| `@if(user)` | `@if (user != null)` |
| nullable `user.name` | `user?.name` |
| raw map `map.name` | `map["name"]` |
| missing values treated as null | pass an explicit nullable value |
| `helper()` | `function()` |

The deprecated `helper()` Dart alias remains during `0.2.x` and will be
removed in `0.3.0`. Removed template syntax has no compatibility aliases.

## Running the checks

```bash
dart analyze
dart test
dart run benchmark/render_benchmark.dart
```

## License

MIT
