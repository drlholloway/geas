import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

// Helpers for the YAML maps in task frontmatter and list files. Field values
// are already encoded: a String, an int, a List<String>, or null.

const _equality = DeepCollectionEquality();

/// [fields] as a block map, in order, with lists in flow style.
String emitYamlMap(Map<String, Object?> fields) {
  final out = StringBuffer();
  fields.forEach((key, value) => out.writeln('$key: ${_value(value)}'));
  return out.toString();
}

/// [source] with each field that differs from [previous] set to its value in
/// [fields]. Comments, formatting, key order and keys not in [fields] are
/// left alone.
String patchYamlMap(
  String source,
  Map<String, Object?> fields,
  Map<String, Object?> previous,
) {
  final editor = YamlEditor(source);
  fields.forEach((key, value) {
    if (_equality.equals(value, previous[key])) return;
    editor.update(
        [key],
        value is List
            ? wrapAsYamlNode(value, collectionStyle: CollectionStyle.FLOW)
            : value);
  });
  final text = editor.toString();
  return text.endsWith('\n') ? text : '$text\n';
}

/// Parses [text] as a YAML map, throwing [FormatException] otherwise.
YamlMap parseYamlMap(String text, String what) {
  final Object? doc;
  try {
    doc = loadYaml(text);
  } on YamlException catch (e) {
    throw FormatException('$what is not valid YAML: ${e.message}');
  }
  if (doc is! YamlMap) throw FormatException('$what must be a YAML map.');
  return doc;
}

/// A required string field. Scalars such as numbers are taken as text.
String requireString(YamlMap map, String key, String what) {
  final value = map[key];
  if (value == null || value is YamlMap || value is YamlList) {
    throw FormatException('$what needs a "$key".');
  }
  return '$value';
}

/// An optional string field.
String? optionalString(YamlMap map, String key, String what) {
  final value = map[key];
  if (value == null) return null;
  if (value is YamlMap || value is YamlList) {
    throw FormatException('"$key" in $what must be a single value.');
  }
  return '$value';
}

String _value(Object? value) => switch (value) {
      null => 'null',
      int() => '$value',
      String() => _scalar(value, inFlow: false),
      List() => '[${value.map((v) => _scalar('$v', inFlow: true)).join(', ')}]',
      _ => throw ArgumentError.value(value, 'value', 'not encodable'),
    };

/// Plain if YAML reads it back as the same string, double-quoted otherwise.
/// JSON strings are valid YAML double-quoted scalars.
String _scalar(String s, {required bool inFlow}) {
  if (s.isEmpty || s.trim() != s || s.contains('\n')) return jsonEncode(s);
  if (inFlow && s.contains(RegExp(r'[,\[\]{}]'))) return jsonEncode(s);
  try {
    if (loadYaml(s) == s) return s;
  } on YamlException {
    // Not plain-safe.
  }
  return jsonEncode(s);
}
