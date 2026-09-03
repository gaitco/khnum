# Khnum Core

<p align="center"><img src="assets/icon.svg" width="96" alt="Khnum Core icon"></p>

Khnum is an HTML template engine for pure Dart servers. It supports layouts,
includes, components, loops, and HTML escaping by default. It uses no Flutter,
code generation, or reflection and works with Shelf, Dart Frog, Serverpod, or
`dart:io`.

```html
{{-- views/dashboard.khnum.html --}}
@extends("layouts.app")

@section("title", title)

@section("content")
<h1>{{ heading }}</h1>

@if(user)
    <x-alert type="success">Welcome back, {{ user.name }}!</x-alert>
@else
    <p>Please log in.</p>
@endif

<ul>
@foreach(items as item)
    <li>{{ item.name }} {{ loop.last ? "" : "|" }}</li>
@endforeach
</ul>
@endsection
```

```dart
import 'package:maat_khnum_core/maat_khnum_core.dart';

final khnum = Khnum(
  viewsPath: 'views',
  environment: TemplateEnvironment.production,
);

final html = await khnum.render('dashboard', {
  'title': 'Dashboard',
  'heading': 'Hello',
  'user': user,        // Map, or any object with toJson()
  'items': items,
});
```

Return it from Shelf:

```dart
Response.ok(html, headers: {'content-type': 'text/html; charset=utf-8'});
```

A complete server is in `example/shelf_example.dart` (`PORT=8080 dart run example/shelf_example.dart`).

## Why not compile templates like Laravel Blade?

Laravel Blade turns `.blade.php` into PHP and lets PHP execute it. Dart has no
`eval`, `dart:mirrors` does not exist in compiled binaries, and code generation
would make every template edit a build step. Khnum instead uses a parsed AST and
a small, safe expression language. Templates cannot run Dart; they read the
data you pass and call the helpers you register.

## What is supported

| Area | Syntax |
|---|---|
| Escaped output | `{{ expr }}` (escapes `& < > " '`; `null` prints nothing) |
| Raw output | `{!! expr !!}`, `HtmlString`, `{{ json(data) }}` for `<script>` |
| Comments, literals | `{{-- --}}`, `@{{ }}`, `@@` |
| Conditionals | `@if / @elseif / @else / @endif`, `@unless / @endunless` |
| Loops | `@foreach(items as item)`, `@foreach(map as k => v)`, `@for(i in items)`, `loop.index/iteration/first/last/count/remaining/even/odd/depth/parent` |
| Layouts | `@extends`, `@section ... @endsection`, `@section("t", value)`, `@yield("s", default)`, `@parent`, `@show`, `@stop` |
| Includes | `@include("view")`, `@include("view", {"k": v})`, shares the parent scope |
| Components | `<x-name attr="s" :attr="expr" flag>`, `{{ slot }}`, `<x-slot name="s">`, `<x-slot:s>`, `@props({...})`, `{{ attributes }}`, `attributes.merge({...})`, `<x-forms.input>` for subdirectories |
| Data | `Map`, `List` (`[i]`, `.length`, `.first`, `.last`), objects via `toJson()`, or `khnum.resolve<T>(...)` |
| Expressions | literals, `.` and `[]`, `+ - * / %`, `== != < <= > >=`, `&& \|\| !`, `??`, `?:`, helper calls |
| Extensibility | `helper()`, `directive()`, `resolve<T>()`, `share()`, custom `TemplateLoader` |
| Modes | development (reload on file change) / production (parse once, in memory) |
| Errors | every exception carries the template name and line |

Truthiness is Khnum-loose: `null`, `false`, `0`, `''` and empty collections are false.

## Intentionally out of scope

`@stack/@push`, `@once`, `@php`, `@verbatim`, `@forelse`, `@switch`, `@auth/@guest`, `@csrf/@method`, `@each`, `@lang`, class-based components, method calls on data (`{{ s.toUpperCase() }}` is an error; use a helper), an on-disk compiled cache, streaming output, and any form of arbitrary Dart evaluation.

## Security

- `{{ }}` escapes; only `{!! !!}`, `HtmlString` and custom directive output are raw.
- View names are validated before any filesystem access and must resolve under the views root, so `../` never works, in `render`, `@include`, `@extends` or components.
- Includes, components and layouts share a depth counter (`maxDepth`, default 64) so recursion throws instead of overflowing.
- Missing variables throw by default (`MissingVariables.throwError`) or evaluate to `null` (`MissingVariables.treatAsNull`).
- Templates are code. Never render templates uploaded by users: they cannot execute Dart, but they can read all of the data you pass and loop indefinitely.

## Performance

`benchmark/render_benchmark.dart` renders a page made of a layout, a partial, two components and a 50-row table from the warm cache:

| Mode | Per render | Throughput |
|---|---|---|
| `dart run` (JIT) | ~115 µs | ~8,600 renders/s |
| `dart compile exe` (AOT) | ~125 µs | ~8,000 renders/s |

Measured on an Apple Silicon laptop with Dart 3.12; run it yourself for your hardware.

## Running the checks

```bash
dart analyze
dart test
dart run benchmark/render_benchmark.dart
PORT=8080 dart run example/shelf_example.dart
```

## License

MIT
