/// HTTP routes on the game server. All JSON. All except `auth/*` need
/// `Authorization: Bearer <accessToken>`.
///
/// The base URL is configured per build (`API_BASE_URL`), so the same app
/// can point at a laptop, a staging box or the production server in
/// Uzbekistan.
abstract final class ApiRoutes {
  static const version = 'v1';

  // Accounts (stream 5)
  static const authPhoneStart = '/v1/auth/phone/start'; // send SMS code
  static const authPhoneVerify = '/v1/auth/phone/verify'; // -> AuthSession
  static const authApple = '/v1/auth/apple'; // -> AuthSession
  static const authRefresh = '/v1/auth/refresh'; // -> AuthSession
  static const me = '/v1/me'; // GET/PATCH profile, DELETE account

  // Rooms (stream 2)
  static const rooms = '/v1/rooms'; // POST CreateRoomRequest -> Room
  static const joinRoom = '/v1/rooms/join'; // POST JoinRoomRequest -> Room
  static const quickMatch = '/v1/rooms/quick'; // POST -> Room
  static String room(String roomId) => '/v1/rooms/$roomId';
  static String leaveRoom(String roomId) => '/v1/rooms/$roomId/leave';

  // Video (stream 3)
  static String callGrant(String roomId) => '/v1/rooms/$roomId/call';

  // Coins (stream 4)
  static const wallet = '/v1/wallet'; // GET -> WalletBalance
  static const ledger = '/v1/wallet/ledger'; // GET -> List<LedgerEntry>
  static const coinPacks = '/v1/shop/packs'; // GET -> List<CoinPack>
  static const purchases = '/v1/shop/purchases'; // POST PurchaseRequest
  static const appStoreNotifications = '/v1/hooks/app-store';
  static const playNotifications = '/v1/hooks/play';

  /// Realtime socket. Connect with `?token=<accessToken>`.
  static const socket = '/v1/ws';

  static const health = '/healthz';
}
