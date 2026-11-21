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
