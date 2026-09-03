import 'ast.dart';
import 'context.dart';
import 'engine.dart';
import 'exceptions.dart';
import 'expression.dart';
import 'html.dart';

class _Section {
  _Section(this.body, this.context);
  final List<Node> body;
  final RenderContext context;
}

/// Per-render state: Khnum's view factory. Sections are global to one
/// `render()` call so an include or a component can fill a layout slot.
class _State {
  final sections = <String, List<_Section>>{};
  final sectionStack = <(String, int)>[];
  int depth = 0;
}

/// Walks a [Template] and writes HTML. One instance per engine; all
/// per-render state lives in [_State].
class Renderer {
  Renderer(this.engine);

  final Khnum engine;

  String render(String view, Map<String, Object?> data) {
    final out = StringBuffer();
    _view(view, {...engine.shared, ...data}, out, _State());
    return out.toString();
  }

  void _view(
    String view,
    Map<String, Object?> data,
    StringBuffer out,
    _State state, {
    String? from,
    int? line,
  }) {
    final template = engine.load(view, from: from, line: line);
    final ctx = RenderContext(engine, template.name, data);
    _template(template, ctx, out, state, from: from, line: line);
  }

  void _template(
    Template template,
    RenderContext ctx,
    StringBuffer out,
    _State state, {
    String? from,
    int? line,
  }) {
    if (++state.depth > engine.maxDepth) {
      throw TemplateRenderException(
        "Maximum render depth (${engine.maxDepth}) exceeded while rendering "
        "'${template.name}'. Check for a recursive @include or component.",
        template: from,
        line: line,
      );
    }
    final extendsView = template.extendsView;
    final nodes = extendsView == null
        ? template.nodes
        // ponytail: Khnum echoes the child's stray whitespace before the
        // layout; dropping whitespace-only text keeps `<!DOCTYPE>` first.
        : [
            for (final n in template.nodes)
              if (n is! TextNode || n.text.trim().isNotEmpty) n,
          ];
    _nodes(nodes, ctx, out, state);
    if (extendsView != null) {
      final parent = _viewName(extendsView.eval(ctx), ctx, extendsView.line);
      _view(
        parent,
        ctx.flatten(),
        out,
        state,
        from: template.name,
        line: extendsView.line,
      );
    }
    state.depth--;
  }

  String _viewName(Object? value, RenderContext ctx, int line) {
    if (value is String) return value;
    throw ctx.error('View name must be a string, got $value', line);
  }

  void _nodes(
    List<Node> nodes,
    RenderContext ctx,
    StringBuffer out,
    _State state,
  ) {
    for (final node in nodes) {
      try {
        _node(node, ctx, out, state);
      } on TemplateException {
        rethrow;
      } catch (e) {
        throw ctx.error(e.toString(), node.line);
      }
    }
  }

  void _node(Node node, RenderContext ctx, StringBuffer out, _State state) {
    switch (node) {
      case TextNode():
        out.write(node.text);
      case EchoNode():
        final value = node.expression.eval(ctx);
        out.write(node.raw ? (value?.toString() ?? '') : escapeHtml(value));
      case IfNode():
        for (final branch in node.branches) {
          if (isTruthy(branch.condition.eval(ctx))) {
            _nodes(branch.body, ctx, out, state);
            return;
          }
        }
        if (node.elseBody != null) _nodes(node.elseBody!, ctx, out, state);
      case ForeachNode():
        _foreach(node, ctx, out, state);
      case SectionNode():
        state.sections
            .putIfAbsent(node.name, () => [])
            .add(_Section(node.body, ctx));
        if (node.yieldsImmediately) _yield(node.name, null, ctx, out, state);
      case YieldNode():
        _yield(node.name, node.defaultValue, ctx, out, state);
      case ParentNode():
        if (state.sectionStack.isEmpty) {
          throw ctx.error('@parent is only valid inside a section', node.line);
        }
        final (name, index) = state.sectionStack.last;
        _section(name, index + 1, out, state);
      case IncludeNode():
        final view = _viewName(node.view.eval(ctx), ctx, node.line);
        final extra = node.data?.eval(ctx);
        if (extra != null && extra is! Map) {
          throw ctx.error('@include data must be a map', node.line);
        }
        _view(
          view,
          {...ctx.flatten(), ...?(extra as Map?)?.cast<String, Object?>()},
          out,
          state,
          from: ctx.template,
          line: node.line,
        );
      case ComponentNode():
        _component(node, ctx, out, state);
      case PropsNode():
        break; // consumed by _component
      case DirectiveNode():
        final handler = engine.directiveFor(node.name)!;
        final args = [for (final a in node.arguments) a.eval(ctx)];
        out.write(handler(ctx, args)?.toString() ?? '');
    }
  }

  void _foreach(
    ForeachNode node,
    RenderContext ctx,
    StringBuffer out,
    _State state,
  ) {
    final value = node.iterable.eval(ctx);
    final List<MapEntry<Object?, Object?>> entries;
    if (value == null) {
      entries = const [];
    } else if (value is Map) {
      entries = [for (final e in value.entries) MapEntry(e.key, e.value)];
    } else if (value is Iterable) {
      var i = 0;
      entries = [for (final v in value) MapEntry(i++, v)];
    } else {
      throw ctx.error(
        'Cannot loop over ${value.runtimeType}; expected a list or map',
        node.line,
      );
    }
    final parentLoop = ctx.has('loop') ? ctx.lookup('loop', node.line) : null;
    final depth = parentLoop is Map ? (parentLoop['depth'] as int) + 1 : 1;
    final count = entries.length;
    final scope = ctx.child();
    for (var i = 0; i < count; i++) {
      scope.set(node.valueName, entries[i].value);
      if (node.keyName != null) scope.set(node.keyName!, entries[i].key);
      scope.set('loop', <String, Object?>{
        'index': i,
        'iteration': i + 1,
        'remaining': count - i - 1,
        'count': count,
        'first': i == 0,
        'last': i == count - 1,
        'even': i.isEven,
        'odd': i.isOdd,
        'depth': depth,
        'parent': parentLoop,
      });
      _nodes(node.body, scope, out, state);
    }
  }

  void _yield(
    String name,
    Expression? defaultValue,
    RenderContext ctx,
    StringBuffer out,
    _State state,
  ) {
    if (state.sections[name]?.isNotEmpty ?? false) {
      _section(name, 0, out, state);
    } else if (defaultValue != null) {
      out.write(escapeHtml(defaultValue.eval(ctx)));
    }
  }

  void _section(String name, int index, StringBuffer out, _State state) {
    final sections = state.sections[name]!;
    if (index >= sections.length) return;
    state.sectionStack.add((name, index));
    _nodes(sections[index].body, sections[index].context, out, state);
    state.sectionStack.removeLast();
  }

  void _component(
    ComponentNode node,
    RenderContext ctx,
    StringBuffer out,
    _State state,
  ) {
    final view = 'components.${node.name}';
    final template = engine.load(view, from: ctx.template, line: node.line);

    final attributes = <String, Object?>{};
    for (final attr in node.attributes) {
      if (attr.parts != null) {
        final buffer = StringBuffer();
        _nodes(attr.parts!, ctx, buffer, state);
        attributes[attr.name] = buffer.toString();
      } else {
        attributes[attr.name] = attr.value == null
            ? true
            : attr.value!.eval(ctx);
      }
    }

    final slots = <String, Object?>{};
    final body = StringBuffer();
    _nodes(node.body, ctx, body, state);
    slots['slot'] = HtmlString(body.toString());
    for (final entry in node.slots.entries) {
      final buffer = StringBuffer();
      _nodes(entry.value, ctx, buffer, state);
      slots[entry.key] = HtmlString(buffer.toString());
    }

    final props = template.nodes.whereType<PropsNode>().firstOrNull;
    final variables = <String, Object?>{...engine.shared};
    final bag = <String, Object?>{...attributes};
    if (props != null) {
      final defaults = props.defaults.eval(ctx);
      if (defaults is! Map) {
        throw TemplateSyntaxException(
          '@props needs a map of defaults, e.g. @props({"type": "info"})',
          template: template.name,
          line: props.line,
        );
      }
      for (final entry in defaults.entries) {
        final name = entry.key.toString();
        variables[name] = attributes.containsKey(name)
            ? attributes[name]
            : entry.value;
        bag.remove(name);
      }
    }
    variables
      ..addAll(attributes)
      ..addAll(slots)
      ..['attributes'] = AttributeBag(bag);

    final componentCtx = RenderContext(engine, template.name, variables);
    _template(
      template,
      componentCtx,
      out,
      state,
      from: ctx.template,
      line: node.line,
    );
  }
}
