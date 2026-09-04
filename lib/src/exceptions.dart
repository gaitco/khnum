/// Base class for every error khnum raises. Always carries the template
/// name and the 1-based line where the problem is, when known.
class TemplateException implements Exception {
  TemplateException(this.message, {this.template, this.line});

  final String message;
  final String? template;
  final int? line;

  @override
  String toString() {
    final where = template == null
        ? ''
        : line == null
        ? ' ($template)'
        : ' ($template:$line)';
    return '$runtimeType: $message$where';
  }
}

/// Malformed template source: unclosed `{{`, unknown `@endfoo`, bad expression.
class TemplateSyntaxException extends TemplateException {
  TemplateSyntaxException(super.message, {super.template, super.line});
}

/// The view name does not map to a file, or is not a legal view name.
class TemplateNotFoundException extends TemplateException {
  TemplateNotFoundException(super.message, {super.template, super.line});
}

/// A variable or key referenced by a template is not in the data.
class UndefinedVariableException extends TemplateException {
  UndefinedVariableException(super.message, {super.template, super.line});
}

/// Runtime failure while rendering: function threw, bad operand types,
/// include recursion past [Khnum.maxDepth].
class TemplateRenderException extends TemplateException {
  TemplateRenderException(super.message, {super.template, super.line});
}
