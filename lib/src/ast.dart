import 'expression.dart';

/// A parsed template. The AST is the contract between the parser and the
/// renderer: any parser that produces these nodes works with the renderer.
class Template {
  Template(this.name, this.nodes, {this.extendsView});

  final String name;
  final List<Node> nodes;

  /// Set by `@extends(...)`; rendered after this template's own body.
  final Expression? extendsView;
}

sealed class Node {
  const Node(this.line);
  final int line;
}

class TextNode extends Node {
  const TextNode(super.line, this.text);
  final String text;
}

/// `{{ expr }}` (escaped) or `{!! expr !!}` (raw).
class EchoNode extends Node {
  const EchoNode(super.line, this.expression, {required this.raw});
  final Expression expression;
  final bool raw;
}

class IfBranch {
  const IfBranch(this.condition, this.body);
  final Expression condition;
  final List<Node> body;
}

/// `@if/@elseif/@else/@endif`.
class IfNode extends Node {
  const IfNode(super.line, this.branches, this.elseBody);
  final List<IfBranch> branches;
  final List<Node>? elseBody;
}

/// `@for (final item in items) ... @endfor`.
class ForNode extends Node {
  const ForNode(super.line, this.iterable, this.valueName, this.body);
  final Expression iterable;
  final String valueName;
  final List<Node> body;
}

/// `@section('name') ... @endsection`, `@section('name', expr)`, and
/// `@section('name') ... @show` ([yieldsImmediately]).
class SectionNode extends Node {
  const SectionNode(
    super.line,
    this.name,
    this.body, {
    this.yieldsImmediately = false,
  });
  final String name;
  final List<Node> body;
  final bool yieldsImmediately;
}

/// `@yield('name')` / `@yield('name', default)`.
class YieldNode extends Node {
  const YieldNode(super.line, this.name, this.defaultValue);
  final String name;
  final Expression? defaultValue;
}

/// `@parent` inside a section: splice in the layout's content.
class ParentNode extends Node {
  const ParentNode(super.line);
}

/// `@include('view')` / `@include('view', {data})`.
class IncludeNode extends Node {
  const IncludeNode(super.line, this.view, this.data);
  final Expression view;
  final Expression? data;
}

/// One attribute on a component tag.
class ComponentAttribute {
  const ComponentAttribute(this.name, {this.value, this.parts});

  final String name;

  /// Bound value for `:name="expr"`, or a literal for `name="text"`;
  /// `null` with no [parts] means a bare boolean attribute (`disabled`).
  final Expression? value;

  /// For `name="text {{ expr }}"`: the interpolated template of the value.
  final List<Node>? parts;
}

/// `<x-name attr="..." :attr="expr">body<x-slot name="s">...</x-slot></x-name>`
class ComponentNode extends Node {
  const ComponentNode(
    super.line,
    this.name,
    this.attributes,
    this.body,
    this.slots,
  );
  final String name;
  final List<ComponentAttribute> attributes;
  final List<Node> body;
  final Map<String, List<Node>> slots;
}

/// `@props({"type": "info"})` at the top of a component template.
class PropsNode extends Node {
  const PropsNode(super.line, this.defaults);
  final Expression defaults;
}

/// A developer-registered directive: `@money(price)`.
class DirectiveNode extends Node {
  const DirectiveNode(super.line, this.name, this.arguments);
  final String name;
  final List<Expression> arguments;
}
