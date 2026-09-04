import 'dart:convert';

// Escape HTML delimiters in text and attributes. `/` stays readable in URLs.
const _escaper = HtmlEscape(
  HtmlEscapeMode(
    name: 'khnum',
    escapeLtGt: true,
    escapeQuot: true,
    escapeApos: true,
  ),
);

/// HTML-escape [value] for use in element content and attribute values.
/// `null` becomes `''`; an [HtmlString] passes through unchanged.
String escapeHtml(Object? value) {
  if (value == null) return '';
  if (value is HtmlString) return value.html;
  if (value is AttributeBag) return value.toString();
  return _escaper.convert(value.toString());
}

/// Marks a string as already-safe HTML so `{{ }}` will not escape it.
/// Construct it only around markup you produced yourself or already sanitised.
class HtmlString {
  const HtmlString(this.html);

  final String html;

  @override
  String toString() => html;
}

/// The `attributes` bag a component receives: every attribute that was not
/// declared in `@props`. Rendering it emits `key="escaped value"` pairs.
class AttributeBag {
  AttributeBag(Map<String, Object?> attributes)
    : _attributes = Map.unmodifiable(attributes);

  final Map<String, Object?> _attributes;

  Map<String, Object?> get all => _attributes;

  Object? operator [](String key) => _attributes[key];

  bool has(String key) => _attributes.containsKey(key);

  /// Merge defaults under incoming attributes and concatenate `class` values.
  AttributeBag merge(Map<String, Object?> defaults) {
    final merged = <String, Object?>{...defaults};
    for (final entry in _attributes.entries) {
      if (entry.key == 'class' && defaults['class'] != null) {
        merged['class'] = '${defaults['class']} ${entry.value}';
      } else {
        merged[entry.key] = entry.value;
      }
    }
    return AttributeBag(merged);
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    for (final entry in _attributes.entries) {
      final value = entry.value;
      if (value == null || value == false) continue;
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(entry.key);
      if (value == true) continue;
      buffer
        ..write('="')
        ..write(escapeHtml(value))
        ..write('"');
    }
    return buffer.toString();
  }
}

/// JSON for use inside `<script>`: `<`, `>`, `&` and U+2028/2029 are
/// escaped as `\uXXXX` so `</script>` inside a string cannot break out.
/// Returned as an [HtmlString] so `{{ json(data) }}` prints it verbatim.
HtmlString toJsonHtml(Object? value) {
  final raw = jsonEncode(value, toEncodable: (v) => (v as dynamic).toJson());
  return HtmlString(
    raw
        .replaceAll('<', r'\u003c')
        .replaceAll('>', r'\u003e')
        .replaceAll('&', r'\u0026')
        .replaceAll('\u2028', r'\u2028')
        .replaceAll('\u2029', r'\u2029'),
  );
}
