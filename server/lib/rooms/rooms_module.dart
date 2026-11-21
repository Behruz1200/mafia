import 'package:contracts/contracts.dart';
import 'package:shelf_router/shelf_router.dart';

import '../src/module.dart';

/// Stream 2 (rooms and game server). Create and join rooms, quick match,
/// run `GameEngine` per match, push state through `lib/realtime`, call
/// `WalletSettlement` at match start and end, handle reconnects.
class RoomsModule extends ServerModule {
  @override
  void mount(Router r) {
    r.post(ApiRoutes.rooms, notImplemented);
    r.post(ApiRoutes.joinRoom, notImplemented);
    r.post(ApiRoutes.quickMatch, notImplemented);
    r.get('/v1/rooms/<roomId>', notImplemented);
    r.post('/v1/rooms/<roomId>/leave', notImplemented);
  }
}
