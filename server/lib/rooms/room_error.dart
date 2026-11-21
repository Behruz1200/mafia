/// A refused room request. [code] is the stable `ApiError` code the app
/// localises; [status] is the HTTP status for REST calls.
class RoomError implements Exception {
  const RoomError(this.code, this.status, [this.message]);

  final String code;
  final int status;
  final String? message;

  static const unauthorized = RoomError('unauthorized', 401);
  static const notFound = RoomError('room_not_found', 404);
  static const full = RoomError('room_full', 409);
  static const inMatch = RoomError('room_in_match', 409);
  static const alreadyPlaying = RoomError('already_in_match', 409);
  static const notMember = RoomError('not_in_room', 403);
  static const notHost = RoomError('not_host', 403);
  static const notEnoughPlayers = RoomError('not_enough_players', 409);
  static const stakesNotAllowed = RoomError('stakes_not_allowed', 403);
  static const insufficientCoins = RoomError('insufficient_coins', 402);
  static const invalidAction = RoomError('invalid_action', 400);
  static const badRequest = RoomError('bad_request', 400);

  @override
  String toString() => 'RoomError($code${message == null ? '' : ': $message'})';
}
