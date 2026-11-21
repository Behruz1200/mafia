import 'package:contracts/contracts.dart';
import 'package:shelf_router/shelf_router.dart';

import '../src/module.dart';

/// Stream 5 (accounts). Phone sign-in by SMS code through a local provider,
/// Sign in with Apple, JWT sessions, profile, account deletion. Profiles are
/// stored only in this server's PostgreSQL database.
class AuthModule extends ServerModule {
  @override
  void mount(Router r) {
    r.post(ApiRoutes.authPhoneStart, notImplemented);
    r.post(ApiRoutes.authPhoneVerify, notImplemented);
    r.post(ApiRoutes.authApple, notImplemented);
    r.post(ApiRoutes.authRefresh, notImplemented);
    r.get(ApiRoutes.me, notImplemented);
    r.patch(ApiRoutes.me, notImplemented);
    r.delete(ApiRoutes.me, notImplemented);
  }
}
