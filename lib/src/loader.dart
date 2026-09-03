import 'dart:io';

import 'package:path/path.dart' as p;

import 'exceptions.dart';

/// The raw text of one template plus a [version] that changes when the
/// source does (mtime for files), so development mode can reload.
class TemplateSource {
  const TemplateSource(this.name, this.source, this.version);

  final String name;
  final String source;
  final Object version;
}

/// Where templates come from. Implement to load from a database, assets
/// bundled in a binary, and so on.
abstract class TemplateLoader {
  /// Returns `null` when no template has this name.
  TemplateSource? load(String name);
}

final _validName = RegExp(r'^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*$');

/// Rejects anything that is not dot-separated identifiers, so `../etc/passwd`
/// never reaches the filesystem. `/` is accepted as a separator alias.
String normalizeViewName(String name) {
  final normalized = name.replaceAll('/', '.');
  if (!_validName.hasMatch(normalized)) {
    throw TemplateNotFoundException(
      "Invalid view name '$name': use letters, digits, '_', '-' and '.' only",
    );
  }
  return normalized;
}

/// Loads `name.with.dots` from `<viewsPath>/name/with/dots<extension>`.
/// Names under `components.` resolve against [componentsPath] when set.
class FileTemplateLoader implements TemplateLoader {
  FileTemplateLoader(
    String viewsPath, {
    String? componentsPath,
    this.extension = '.khnum.html',
  }) : _root = p.canonicalize(viewsPath),
       _componentsRoot = componentsPath == null
           ? null
           : p.canonicalize(componentsPath);

  final String _root;
  final String? _componentsRoot;
  final String extension;

  @override
  TemplateSource? load(String name) {
    final normalized = normalizeViewName(name);
    var segments = normalized.split('.');
    var root = _root;
    if (_componentsRoot != null &&
        segments.length > 1 &&
        segments.first == 'components') {
      root = _componentsRoot;
      segments = segments.sublist(1);
    }
    final file = File(p.joinAll([root, ...segments]) + extension);
    if (!p.isWithin(root, p.canonicalize(file.path))) {
      throw TemplateNotFoundException("View '$name' escapes the views root");
    }
    if (!file.existsSync()) return null;
    return TemplateSource(
      normalized,
      file.readAsStringSync(),
      file.lastModifiedSync(),
    );
  }
}

/// Templates from a map; handy for tests and for binaries that embed views.
class MemoryTemplateLoader implements TemplateLoader {
  MemoryTemplateLoader(this.templates);

  final Map<String, String> templates;

  @override
  TemplateSource? load(String name) {
    final normalized = normalizeViewName(name);
    final source = templates[normalized];
    if (source == null) return null;
    return TemplateSource(normalized, source, source.hashCode);
  }
}
