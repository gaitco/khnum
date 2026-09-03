import 'ast.dart';
import 'context.dart';
import 'exceptions.dart';
import 'html.dart';
import 'loader.dart';
import 'parser.dart';
import 'renderer.dart';

/// Controls reloading: development re-reads a template whose file changed;
/// production parses each template once and never touches the disk again.
enum TemplateEnvironment { development, production }

/// What happens when a template reads a variable or key that is not there.
enum MissingVariables {
  /// Throw [UndefinedVariableException] naming the template and line.
  throwError,

  /// Evaluate to `null`, which `{{ }}` prints as an empty string.
  treatAsNull,
}

/// A function templates may call: `{{ upper(name) }}`.
typedef Helper = Object? Function(List<Object?> arguments);

/// A custom directive: `@money(price)`. Receives the evaluated arguments and
/// the current [RenderContext]; whatever it returns is written **unescaped**,
/// so call [escapeHtml] on anything that came from a user.
typedef DirectiveHandler =
    Object? Function(RenderContext context, List<Object?> arguments);

/// Resolves `value.key` for objects that are neither maps nor `toJson()`
/// classes. Return `null` for an unknown key.
typedef PropertyResolver<T> = Object? Function(T value, String key);

class _Compiled {
  _Compiled(this.template, this.version);
  final Template template;
  final Object version;
}

class _Resolver {
  _Resolver(this.matches, this.resolve);
  final bool Function(Object) matches;
  final Object? Function(Object, String) resolve;
}

/// The template engine. Create one per application, register helpers and
/// directives at startup, then call [render] per request.
///
/// ```dart
/// final khnum = Khnum(viewsPath: 'resources/views');
/// final html = await khnum.render('home', {'title': 'Home'});
/// ```
class Khnum {
  /// Templates on disk under [viewsPath]; `<x-foo>` components under
  /// [componentsPath] (default `<viewsPath>/components`).
  Khnum({
    required String viewsPath,
    String? componentsPath,
    String extension = '.khnum.html',
    TemplateEnvironment environment = TemplateEnvironment.development,
    MissingVariables missingVariables = MissingVariables.throwError,
    int maxDepth = 64,
  }) : this.withLoader(
         FileTemplateLoader(
           viewsPath,
           componentsPath: componentsPath,
           extension: extension,
         ),
         environment: environment,
         missingVariables: missingVariables,
         maxDepth: maxDepth,
       );

  /// Templates from a map keyed by view name (`'layouts.app'`). Used by
  /// tests and by binaries that embed their views.
  Khnum.inMemory(
    Map<String, String> templates, {
    TemplateEnvironment environment = TemplateEnvironment.development,
    MissingVariables missingVariables = MissingVariables.throwError,
    int maxDepth = 64,
  }) : this.withLoader(
         MemoryTemplateLoader(templates),
         environment: environment,
         missingVariables: missingVariables,
         maxDepth: maxDepth,
       );

  /// Templates from any [TemplateLoader].
  Khnum.withLoader(
    this.loader, {
    this.environment = TemplateEnvironment.development,
    this.missingVariables = MissingVariables.throwError,
    this.maxDepth = 64,
  }) {
    helper('upper', (a) => a.first?.toString().toUpperCase());
    helper('lower', (a) => a.first?.toString().toLowerCase());
    helper('count', (a) {
      final v = a.first;
      return v is Iterable
          ? v.length
          : v is Map
          ? v.length
          : 0;
    });
    helper('json', (a) => toJsonHtml(a.first));
  }

  final TemplateLoader loader;
  final TemplateEnvironment environment;
  final MissingVariables missingVariables;

  /// How many nested includes, components and layouts a render may stack
  /// before it is treated as infinite recursion.
  final int maxDepth;

  final _cache = <String, _Compiled>{};
  final _helpers = <String, Helper>{};
  final _directives = <String, DirectiveHandler>{};
  final _resolvers = <_Resolver>[];
  final _shared = <String, Object?>{};
  late final _renderer = Renderer(this);

  /// Variables available to every template (Laravel's `View::share`).
  Map<String, Object?> get shared => _shared;

  void share(String name, Object? value) => _shared[name] = value;

  /// Register `{{ name(...) }}`.
  void helper(String name, Helper fn) => _helpers[name] = fn;

  /// Register `@name(...)`. Must happen before the first render of any
  /// template that uses it, because unknown `@words` are plain text.
  void directive(String name, DirectiveHandler fn) {
    if (builtInDirectives.contains(name)) {
      throw ArgumentError.value(name, 'name', 'is a built-in directive');
    }
    _directives[name] = fn;
    _cache.clear();
  }

  /// Teach `{{ value.key }}` how to read a [T] that has no `toJson()`.
  void resolve<T extends Object>(PropertyResolver<T> fn) =>
      _resolvers.add(_Resolver((v) => v is T, (v, key) => fn(v as T, key)));

  Helper? helperFor(String name) => _helpers[name];

  DirectiveHandler? directiveFor(String name) => _directives[name];

  bool isDirective(String name) =>
      builtInDirectives.contains(name) || _directives.containsKey(name);

  Object? Function(Object, String)? resolverFor(Object value) =>
      _resolvers.where((r) => r.matches(value)).firstOrNull?.resolve;

  /// Render [view] with [data]. Async for API symmetry with loaders that
  /// will read from the network; the file loader is synchronous.
  Future<String> render(
    String view, [
    Map<String, Object?> data = const {},
  ]) async => renderSync(view, data);

  String renderSync(String view, [Map<String, Object?> data = const {}]) =>
      _renderer.render(view, data);

  /// Whether a template with this name exists.
  bool exists(String view) {
    try {
      return loader.load(view) != null;
    } on TemplateNotFoundException {
      return false;
    }
  }

  /// Parse [view] (from cache when fresh). [from] and [line] name the
  /// template that asked for it, for the error message when it is missing.
  Template load(String view, {String? from, int? line}) {
    final String name;
    try {
      name = normalizeViewName(view);
    } on TemplateNotFoundException catch (e) {
      throw TemplateNotFoundException(e.message, template: from, line: line);
    }
    final cached = _cache[name];
    if (cached != null && environment == TemplateEnvironment.production) {
      return cached.template;
    }
    final source = loader.load(name);
    if (source == null) {
      throw TemplateNotFoundException(
        "View '$name' not found",
        template: from,
        line: line,
      );
    }
    if (cached != null && cached.version == source.version) {
      return cached.template;
    }
    final template = Parser.parseSource(
      source.source,
      name,
      isDirective: isDirective,
    );
    _cache[name] = _Compiled(template, source.version);
    return template;
  }
}
