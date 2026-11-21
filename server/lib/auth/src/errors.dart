/// A failure the app shows to the player. [code] is the stable machine
/// code from `ApiError`; the app translates it.
class AuthError implements Exception {
  const AuthError(this.status, this.code, [this.message]);

  final int status;
  final String code;
  final String? message;

  static const invalidPhone = AuthError(400, 'invalid_phone');
  static const countryNotSupported = AuthError(403, 'country_not_supported');
  static const codeTooSoon = AuthError(429, 'code_too_soon');
  static const tooManyCodes = AuthError(429, 'too_many_codes');
  static const codeInvalid = AuthError(400, 'code_invalid');
  static const codeExpired = AuthError(400, 'code_expired');
  static const tooManyAttempts = AuthError(429, 'too_many_attempts');
  static const smsFailed = AuthError(502, 'sms_failed');
  static const appleTokenInvalid = AuthError(401, 'apple_token_invalid');
  static const appleNotConfigured = AuthError(503, 'apple_not_configured');
  static const refreshInvalid = AuthError(401, 'refresh_invalid');
  static const unauthorized = AuthError(401, 'unauthorized');
  static const accountNotFound = AuthError(404, 'account_not_found');
  static const invalidName = AuthError(400, 'invalid_name');
  static const invalidLocale = AuthError(400, 'invalid_locale');
  static const invalidBirthDate = AuthError(400, 'invalid_birth_date');
  static const birthDateAlreadySet = AuthError(409, 'birth_date_already_set');
  static const badRequest = AuthError(400, 'bad_request');

  @override
  String toString() =>
      'AuthError($status, $code${message == null ? '' : ', $message'})';
}
