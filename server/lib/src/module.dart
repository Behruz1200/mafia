import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// One area of the server (auth, rooms, wallet, ...). Each stream owns its
/// module folder and only touches `lib/src/app.dart` to register it.
abstract class ServerModule {
  /// Adds this module's routes. Paths come from `ApiRoutes` in contracts.
  void mount(Router router);
}

/// JSON response helper.
Response json(Object? body, {int status = 200}) => Response(
  status,
  body: jsonEncode(body),
  headers: const {'content-type': 'application/json'},
);

/// Placeholder until a stream fills in a route.
Response notImplemented(Request _) => json({
  'error': 'not_implemented',
  'message': 'Coming in a later stream',
}, status: 501);
