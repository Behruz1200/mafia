import '../json.dart';
import '../models/call.dart';
import '../models/room.dart';
import '../models/wallet.dart';

class CreateRoomRequest {
  const CreateRoomRequest({required this.settings});
  final RoomSettings settings;
  Json toJson() => {'settings': settings.toJson()};
  factory CreateRoomRequest.fromJson(Json j) => CreateRoomRequest(
    settings: RoomSettings.fromJson(j['settings']! as Json),
  );
}

class JoinRoomRequest {
  const JoinRoomRequest({required this.inviteCode});
  final String inviteCode;
  Json toJson() => {'inviteCode': inviteCode};
  factory JoinRoomRequest.fromJson(Json j) =>
      JoinRoomRequest(inviteCode: j['inviteCode']! as String);
}

class CallGrantRequest {
  const CallGrantRequest({required this.channel});
  final CallChannel channel;
  Json toJson() => {'channel': channel.name};
  factory CallGrantRequest.fromJson(Json j) =>
      CallGrantRequest(channel: decodeEnum(CallChannel.values, j['channel']));
}

class PhoneStartRequest {
  const PhoneStartRequest({required this.phoneE164});
  final String phoneE164;
  Json toJson() => {'phone': phoneE164};
  factory PhoneStartRequest.fromJson(Json j) =>
      PhoneStartRequest(phoneE164: j['phone']! as String);
}

class PhoneVerifyRequest {
  const PhoneVerifyRequest({required this.phoneE164, required this.code});
  final String phoneE164;
  final String code;
  Json toJson() => {'phone': phoneE164, 'code': code};
  factory PhoneVerifyRequest.fromJson(Json j) => PhoneVerifyRequest(
    phoneE164: j['phone']! as String,
    code: j['code']! as String,
  );
}

/// Body of `ApiRoutes.authApple`, from the Sign in with Apple sheet.
class AppleSignInRequest {
  const AppleSignInRequest({
    required this.identityToken,
    required this.rawNonce,
    this.authorizationCode,
    this.displayName,
  });

  /// The JWT Apple returns. The server checks its signature and audience.
  final String identityToken;

  /// The nonce the app made; Apple signed its SHA-256 into the token.
  final String rawNonce;
  final String? authorizationCode;

  /// Apple only shares the name on the very first sign-in.
  final String? displayName;

  Json toJson() => {
    'identityToken': identityToken,
    'rawNonce': rawNonce,
    'authorizationCode': authorizationCode,
    'displayName': displayName,
  };

  factory AppleSignInRequest.fromJson(Json j) => AppleSignInRequest(
    identityToken: j['identityToken']! as String,
    rawNonce: j['rawNonce']! as String,
    authorizationCode: j['authorizationCode'] as String?,
    displayName: j['displayName'] as String?,
  );
}

/// Body of `ApiRoutes.authRefresh` and `ApiRoutes.authSignOut`.
class RefreshRequest {
  const RefreshRequest({required this.refreshToken});
  final String refreshToken;
  Json toJson() => {'refreshToken': refreshToken};
  factory RefreshRequest.fromJson(Json j) =>
      RefreshRequest(refreshToken: j['refreshToken']! as String);
}

/// Body of `PATCH ApiRoutes.me`. Every field is optional; only the ones
/// sent change. `birthDate` (`YYYY-MM-DD`) can be set once, for the age
/// gate.
class UpdateProfileRequest {
  const UpdateProfileRequest({
    this.displayName,
    this.avatarUrl,
    this.locale,
    this.birthDate,
  });

  final String? displayName;
  final String? avatarUrl;
  final String? locale;
  final DateTime? birthDate;

  Json toJson() => {
    if (displayName != null) 'displayName': displayName,
    if (avatarUrl != null) 'avatarUrl': avatarUrl,
    if (locale != null) 'locale': locale,
    if (birthDate != null) 'birthDate': encodeDate(birthDate!),
  };

  factory UpdateProfileRequest.fromJson(Json j) => UpdateProfileRequest(
    displayName: j['displayName'] as String?,
    avatarUrl: j['avatarUrl'] as String?,
    locale: j['locale'] as String?,
    birthDate: j['birthDate'] == null
        ? null
        : DateTime.parse(j['birthDate']! as String),
  );
}

/// Sent after the store reports a purchase. The server verifies it with the
/// store before any coins are credited.
class PurchaseRequest {
  const PurchaseRequest({
    required this.store,
    required this.productId,
    required this.transactionId,
    required this.verificationData,
  });

  final Store store;
  final String productId;
  final String transactionId;

  /// App Store signed transaction (JWS) or Play purchase token.
  final String verificationData;

  Json toJson() => {
    'store': store.name,
    'productId': productId,
    'transactionId': transactionId,
    'verificationData': verificationData,
  };

  factory PurchaseRequest.fromJson(Json j) => PurchaseRequest(
    store: decodeEnum(Store.values, j['store']),
    productId: j['productId']! as String,
    transactionId: j['transactionId']! as String,
    verificationData: j['verificationData']! as String,
  );
}

/// Error body for every non-2xx response.
class ApiError {
  const ApiError({required this.code, this.message});

  /// Stable machine code, e.g. `insufficient_coins`, `room_full`,
  /// `stakes_not_allowed`, `invalid_action`. The app localises it.
  final String code;
  final String? message;

  Json toJson() => {'error': code, 'message': message};
  factory ApiError.fromJson(Json j) =>
      ApiError(code: j['error']! as String, message: j['message'] as String?);
}
