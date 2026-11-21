/// Phone numbers travel in E.164: `+998901234567`.
final _e164 = RegExp(r'^\+[1-9]\d{7,14}$');

/// Calling codes we can map to a country. Longest prefix wins. Add a line
/// here when a new country launches (and add it to `LAUNCH_COUNTRIES`).
const _callingCodes = <String, String>{
  '998': 'UZ',
  '996': 'KG',
  '992': 'TJ',
  '993': 'TM',
  '7': 'RU', // also KZ; see below
  '77': 'KZ',
};

/// Trims spaces, dashes and brackets. Returns null when it is not E.164.
String? normalizePhone(String input) {
  final s = input.replaceAll(RegExp(r'[\s\-()]'), '');
  return _e164.hasMatch(s) ? s : null;
}

/// ISO country code for an E.164 number, or null when we do not know it.
String? countryOfPhone(String e164) {
  final digits = e164.substring(1);
  for (var len = 3; len >= 1; len--) {
    if (digits.length < len) continue;
    final c = _callingCodes[digits.substring(0, len)];
    if (c != null) return c;
  }
  return null;
}

/// `+998901234567` -> `+998 ** *** 45 67`, for logs.
String maskPhone(String e164) => e164.length < 6
    ? '***'
    : '${e164.substring(0, 4)}****${e164.substring(e164.length - 4)}';
