import 'package:contracts/contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/auth_module.dart';
import '../call/call_module.dart';
import '../realtime/socket_handler.dart';
import '../rooms/rooms_module.dart';
import '../wallet/wallet_module.dart';
import 'module.dart';

/// Builds the whole HTTP app. Each stream registers its module here once.
Handler buildApp() {
  final router = Router()
    ..get(ApiRoutes.health, (Request _) => json({'ok': true}))
    ..get(ApiRoutes.socket, socketHandler());

  for (final ServerModule m in [
    AuthModule(),
    RoomsModule(),
    CallModule(),
    WalletModule(),
  ]) {
    m.mount(router);
  }

  return const Pipeline().addMiddleware(logRequests()).addHandler(router.call);
}
