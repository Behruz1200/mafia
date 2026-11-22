import 'package:contracts/contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_guard.dart';
import '../auth/auth_module.dart';
import '../auth/auth_players.dart';
import '../call/call_module.dart';
import '../rooms/ports.dart' show FreeMatchesOnlyWallet;
import '../rooms/call_link.dart';
import '../rooms/rooms_module.dart';
import '../wallet/wallet_module.dart';
import 'module.dart';

/// The rooms module wired to the real parts: profiles from [auth], the
/// coin wallet when there is a database (free games otherwise).
RoomsModule defaultRooms(AuthModule auth) => RoomsModule.fromEnvironment(
  players: AuthPlayers(auth),
  wallet: WalletServices.instance?.wallet ?? const FreeMatchesOnlyWallet(),
);

/// Builds the whole HTTP app. Each stream registers its module here once.
///
/// [rooms] defaults to [defaultRooms]; tests pass their own. Pass the same
/// [auth] the rooms module was built with.
Handler buildApp({RoomsModule? rooms, AuthModule? auth}) {
  // Other modules may use `auth.profileOf` for players' names and age.
  final authModule = auth ?? AuthModule();
  final roomsModule = rooms ?? defaultRooms(authModule);
  // Video: LiveKit tokens for room members, and mutes that follow the game.
  final callService = CallModule().service;
  final call = CallModule(
    service: callService,
    directory: RoomsCallLink(
      rooms: roomsModule.service,
      hub: roomsModule.hub,
      call: callService,
    ),
  );
  final router = Router()
    ..get(ApiRoutes.health, (Request _) => json({'ok': true}))
    ..get(ApiRoutes.socket, roomsModule.socket);

  for (final ServerModule m in [
    authModule,
    roomsModule,
    call,
    WalletModule(),
  ]) {
    m.mount(router);
  }

  return const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(authenticate())
      .addHandler(router.call);
}
