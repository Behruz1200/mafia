import 'package:contracts/contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_guard.dart';
import '../auth/auth_module.dart';
import '../call/call_module.dart';
import '../realtime/socket_handler.dart';
import '../rooms/rooms_module.dart';
import '../wallet/wallet_module.dart';
import 'module.dart';

/// Builds the whole HTTP app. Each stream registers its module here once.
Handler buildApp() {
  // Other modules may use `auth.profileOf` for players' names and age.
  final auth = AuthModule();
  final router = Router()
    ..get(ApiRoutes.health, (Request _) => json({'ok': true}))
    ..get(ApiRoutes.socket, socketHandler());

  for (final ServerModule m in [
    auth,
    RoomsModule(),
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
