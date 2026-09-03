import 'engine.dart';
import 'exceptions.dart';
import 'html.dart';

/// The variables visible while rendering one template, plus the services an
/// expression needs (member resolution, helpers). Loops and components open
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
    if (target == null) return null;
    if (target is Map) {
      if (target.containsKey(key)) return target[key];
      return _missing("Undefined key '$key'", line);
    }
    if (target is AttributeBag) return target[key];
    if (target is List) {
      return switch (key) {
        'length' => target.length,
        'isEmpty' => target.isEmpty,
        'isNotEmpty' => target.isNotEmpty,
        'first' => target.isEmpty ? null : target.first,
        'last' => target.isEmpty ? null : target.last,
        _ => throw error("Lists have no property '$key'", line),
      };
    }
    if (target is String && key == 'length') return target.length;
    final resolver = engine.resolverFor(target);
    if (resolver != null) return resolver(target, key);
    final json = _asJson(target);
    if (json != null) return member(json, key, line);
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
    if (target == null) return null;
    if (target is List) {
      if (key is! int) throw error('List index must be an integer', line);
      if (key < 0 || key >= target.length) {
        return _missing('Index $key out of range (${target.length})', line);
      }
      return target[key];
    }
    return member(target, key.toString(), line);
  }

  Object? call(String name, List<Object?> args, int line) {
    final helper = engine.helperFor(name);
    if (helper == null) throw error("Unknown helper '$name'", line);
    try {
      return helper(args);
    } on TemplateException {
      rethrow;
    } catch (e) {
      throw error("Helper '$name' failed: $e", line);
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
      'registered helpers, e.g. $name(value)',
      line,
    );
  }

  Object? _missing(String message, int line) {
    if (engine.missingVariables == MissingVariables.treatAsNull) return null;
    throw UndefinedVariableException(message, template: template, line: line);
  }

  TemplateRenderException error(String message, int line) =>
      TemplateRenderException(message, template: template, line: line);
}
