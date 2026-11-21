import 'package:contracts/contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_module.dart';
import '../call/call_module.dart';
import '../rooms/ports.dart' show FreeMatchesOnlyWallet;
import '../rooms/rooms_module.dart';
import '../wallet/wallet_module.dart';
import 'module.dart';

/// Builds the whole HTTP app. Each stream registers its module here once.
///
/// [rooms] is built from environment variables unless given (tests pass
/// their own).
Handler buildApp({RoomsModule? rooms}) {
  final roomsModule =
      rooms ??
      RoomsModule.fromEnvironment(
        // The real coin wallet when there is a database; free games otherwise.
        wallet:
            WalletServices.instance?.wallet ?? const FreeMatchesOnlyWallet(),
      );
  final router = Router()
    ..get(ApiRoutes.health, (Request _) => json({'ok': true}))
    ..get(ApiRoutes.socket, roomsModule.socket);

  for (final ServerModule m in [
    AuthModule(),
    roomsModule,
    CallModule(),
    WalletModule(),
  ]) {
    m.mount(router);
  }

  return const Pipeline().addMiddleware(logRequests()).addHandler(router.call);
}
