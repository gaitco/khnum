## 0.1.0

Initial release.

- File-based templates with nested directories, development reload on file change, in-memory cache in production.
- `{{ }}` escaped output, `{!! !!}` raw output, `HtmlString`, `json()` helper safe for `<script>`.
- Restricted expression language: literals, member and index access, arithmetic, comparison, logic, `??`, `?:`, helper calls.
- `@if/@elseif/@else`, `@unless`, `@foreach` with `key => value` and a `loop` variable, `@for`.
- Layouts: `@extends`, `@section`, `@yield` with default, `@parent`, `@show`, inline sections.
- `@include` with scope sharing and data override.
- Anonymous components: attributes, `:bound` attributes, interpolated attributes, `slot`, named slots, `@props`, `attributes` bag with `merge`.
- Extensibility: `helper()`, `directive()`, `resolve<T>()`, `share()`, custom `TemplateLoader`.
- Errors carry template name and line; path traversal and recursion are rejected.
