import 'package:contracts/contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_guard.dart';
import '../auth/auth_module.dart';
import '../auth/auth_players.dart';
import '../call/call_module.dart';
import '../rooms/rooms_module.dart';
import '../wallet/wallet_module.dart';
import 'module.dart';

/// Builds the whole HTTP app. Each stream registers its module here once.
///
/// [rooms] is built from environment variables unless given (tests pass
/// their own).
Handler buildApp({RoomsModule? rooms}) {
  // Other modules may use `auth.profileOf` for players' names and age.
  final auth = AuthModule();
  final roomsModule =
      rooms ?? RoomsModule.fromEnvironment(players: AuthPlayers(auth));
  final router = Router()
    ..get(ApiRoutes.health, (Request _) => json({'ok': true}))
    ..get(ApiRoutes.socket, roomsModule.socket);

  for (final ServerModule m in [
    auth,
    roomsModule,
    CallModule(),
    WalletModule(),
  ]) {
    m.mount(router);
  }

  return const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(authenticate())
      .addHandler(router.call);
}
