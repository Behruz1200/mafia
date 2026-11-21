import 'package:shelf_router/shelf_router.dart';

import '../src/module.dart';

/// Stream 3 (video). Mints LiveKit tokens (`CallGrant`) for the self-hosted
/// LiveKit server, and mutes or moves players when the phase changes.
class CallModule extends ServerModule {
  @override
  void mount(Router r) {
    r.post('/v1/rooms/<roomId>/call', notImplemented);
  }
}
