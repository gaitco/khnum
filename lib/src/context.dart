import 'engine.dart';
import 'exceptions.dart';
import 'html.dart';

/// Metadata exposed as `loop` inside `@for` without pretending it is a map.
class LoopInfo {
  const LoopInfo({
    required this.index,
    required this.count,
    required this.depth,
    this.parent,
  });

  final int index;
  final int count;
  final int depth;
  final LoopInfo? parent;

  int get iteration => index + 1;
  int get remaining => count - index - 1;
  bool get first => index == 0;
  bool get last => index == count - 1;
  bool get even => index.isEven;
  bool get odd => index.isOdd;
}

/// The variables visible while rendering one template, plus the services an
/// expression needs (member resolution, registered functions). Loops and components open
/// child contexts; lookups fall through to the parent frame.
class RenderContext {
  RenderContext(
    this.engine,
    this.template,
    Map<String, Object?> variables, {
    RenderContext? parent,
  }) : _variables = Map.of(variables),
       _parent = parent,
       _jsonCache = parent?._jsonCache ?? Map.identity();

  final Khnum engine;

  /// Name of the template being rendered; used in error messages.
  final String template;

  final Map<String, Object?> _variables;
  final RenderContext? _parent;
  final Map<Object, Map<String, Object?>> _jsonCache;

  static const _absent = Object();

  /// A frame on top of this one: sees everything here, writes stay local.
  RenderContext child([Map<String, Object?> variables = const {}]) =>
      RenderContext(engine, template, variables, parent: this);

  void set(String name, Object? value) => _variables[name] = value;

  bool has(String name) =>
      _variables.containsKey(name) || (_parent?.has(name) ?? false);

  /// Every visible variable, innermost frame winning. What `@include` shares.
  Map<String, Object?> flatten() => {...?_parent?.flatten(), ..._variables};

  Object? lookup(String name, int line) {
    final found = _find(name);
    if (!identical(found, _absent)) return found;
    return _missing("Undefined variable '$name'", line);
  }

  Object? _find(String name) {
    if (_variables.containsKey(name)) return _variables[name];
    return _parent?._find(name) ?? _absent;
  }

  Object? member(Object? target, String key, int line) {
    if (target == null) {
      throw error("Cannot read '$key' from null; use '?.'", line);
    }
    if (target is AttributeBag) return target[key];
    if (target is LoopInfo) {
      return switch (key) {
        'index' => target.index,
        'iteration' => target.iteration,
        'remaining' => target.remaining,
        'count' => target.count,
        'first' => target.first,
        'last' => target.last,
        'even' => target.even,
        'odd' => target.odd,
        'depth' => target.depth,
        'parent' => target.parent,
        _ => throw error("Loop metadata has no property '$key'", line),
      };
    }
    if (target is Map) {
      return switch (key) {
        'length' => target.length,
        'isEmpty' => target.isEmpty,
        'isNotEmpty' => target.isNotEmpty,
        'keys' => target.keys,
        'values' => target.values,
        'entries' => target.entries,
        _ => throw error(
          "Maps have no property '$key'; use brackets for map keys",
          line,
        ),
      };
    }
    if (target is List) {
      return switch (key) {
        'length' => target.length,
        'isEmpty' => target.isEmpty,
        'isNotEmpty' => target.isNotEmpty,
        'first' =>
          target.isEmpty
              ? throw error('Cannot read first from an empty list', line)
              : target.first,
        'last' =>
          target.isEmpty
              ? throw error('Cannot read last from an empty list', line)
              : target.last,
        _ => throw error("Lists have no property '$key'", line),
      };
    }
    if (target is String) {
      return switch (key) {
        'length' => target.length,
        'isEmpty' => target.isEmpty,
        'isNotEmpty' => target.isNotEmpty,
        _ => throw error("Strings have no property '$key'", line),
      };
    }
    if (target is Iterable) {
      return switch (key) {
        'length' => target.length,
        'isEmpty' => target.isEmpty,
        'isNotEmpty' => target.isNotEmpty,
        'first' =>
          target.isEmpty
              ? throw error('Cannot read first from an empty iterable', line)
              : target.first,
        'last' =>
          target.isEmpty
              ? throw error('Cannot read last from an empty iterable', line)
              : target.last,
        _ => throw error("Iterables have no property '$key'", line),
      };
    }
    if (target is MapEntry) {
      return switch (key) {
        'key' => target.key,
        'value' => target.value,
        _ => throw error("Map entries have no property '$key'", line),
      };
    }
    final resolver = engine.resolverFor(target);
    if (resolver != null) return resolver(target, key);
    final json = _asJson(target);
    if (json != null) {
      if (json.containsKey(key)) return json[key];
      return _missing("Undefined property '$key'", line);
    }
    throw error(
      "Cannot read '$key' from ${target.runtimeType}: pass a Map, give the "
      'class a toJson() method, or register a resolver with engine.resolve<T>()',
      line,
    );
  }

  Map<String, Object?>? _asJson(Object target) {
    if (_jsonCache.containsKey(target)) return _jsonCache[target];
    Object? json;
    try {
      json = (target as dynamic).toJson();
    } on NoSuchMethodError {
      return null;
    }
    if (json is! Map) return null;
    return _jsonCache[target] = json.cast<String, Object?>();
  }

  Object? index(Object? target, Object? key, int line) {
    if (target == null) {
      throw error('Cannot index null; use ?[...]', line);
    }
    if (target is Map) {
      if (target.containsKey(key)) return target[key];
      return _missing("Undefined key '$key'", line);
    }
    if (target is AttributeBag) return target[key.toString()];
    if (target is List) {
      if (key is! int) throw error('List index must be an integer', line);
      if (key < 0 || key >= target.length) {
        return _missing('Index $key out of range (${target.length})', line);
      }
      return target[key];
    }
    if (target is String) {
      if (key is! int) throw error('String index must be an integer', line);
      if (key < 0 || key >= target.length) {
        return _missing('Index $key out of range (${target.length})', line);
      }
      return target[key];
    }
    throw error('Cannot index ${target.runtimeType}', line);
  }

  Object? call(String name, List<Object?> args, int line) {
    final function = engine.functionFor(name);
    if (function == null) throw error("Unknown function '$name'", line);
    try {
      return function(args);
    } on TemplateException {
      rethrow;
    } catch (e) {
      throw error("Function '$name' failed: $e", line);
    }
  }

  Object? callMethod(
    Object? target,
    String name,
    List<Object?> args,
    int line,
  ) {
    if (target is AttributeBag) {
      switch (name) {
        case 'merge':
          return target.merge(
            (args.firstOrNull as Map?)?.cast<String, Object?>() ?? const {},
          );
        case 'has':
          return target.has(args.first.toString());
        case 'get':
          return target[args.first.toString()];
      }
    }
    throw error(
      "Cannot call '$name' on ${target.runtimeType}: templates only call "
      'registered functions, e.g. $name(value)',
      line,
    );
  }

  Object? _missing(String message, int line) {
    throw UndefinedVariableException(message, template: template, line: line);
  }

  TemplateRenderException error(String message, int line) =>
      TemplateRenderException(message, template: template, line: line);
}
