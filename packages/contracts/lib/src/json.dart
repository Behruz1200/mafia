/// Small helpers shared by the hand-written `toJson` / `fromJson` methods.
///
/// We avoid code generation in the contracts package on purpose: every
/// stream reads these files, so they should stay plain Dart that anyone can
/// follow without running build_runner.
library;

typedef Json = Map<String, Object?>;

/// Timestamps travel as ISO-8601 UTC strings.
String encodeTime(DateTime t) => t.toUtc().toIso8601String();
DateTime decodeTime(Object? v) => DateTime.parse(v! as String).toUtc();
DateTime? decodeTimeOrNull(Object? v) => v == null ? null : decodeTime(v);

T decodeEnum<T extends Enum>(List<T> values, Object? name) =>
    values.byName(name! as String);

List<T> decodeList<T>(Object? v, T Function(Json) f) => [
  for (final e in (v as List? ?? const [])) f(e as Json),
];

List<String> decodeStrings(Object? v) => [
  for (final e in (v as List? ?? const [])) e as String,
];
