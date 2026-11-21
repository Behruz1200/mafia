import '../../l10n/generated/app_localizations.dart';
import 'data/api.dart';

/// Player-facing text for a failed accounts call.
String authErrorText(AppLocalizations t, Object error) {
  final code = error is ApiException ? error.code : '';
  return switch (code) {
    'invalid_phone' => t.authErrorInvalidPhone,
    'country_not_supported' => t.authErrorCountry,
    'code_too_soon' => t.authErrorTooSoon,
    'too_many_codes' => t.authErrorTooManyCodes,
    'code_invalid' => t.authErrorCodeInvalid,
    'code_expired' => t.authErrorCodeExpired,
    'too_many_attempts' => t.authErrorTooManyAttempts,
    'sms_failed' => t.authErrorSms,
    'invalid_name' => t.authErrorName,
    'invalid_birth_date' || 'birth_date_already_set' => t.authErrorBirthDate,
    ApiException.network => t.authErrorNetwork,
    _ => t.authErrorGeneric,
  };
}
