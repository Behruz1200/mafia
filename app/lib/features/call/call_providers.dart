import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import 'call_session.dart';
import 'data/http_call_grant_source.dart';

/// Where call grants come from: the game server, or a fake offline.
final callGrantSourceProvider = Provider<CallGrantSource>(
  (ref) => AppConfig.useFakes
      ? FakeCallGrantSource()
      : HttpCallGrantSource(
          baseUrl: AppConfig.apiBaseUrl,
          accessToken: () =>
              ref.read(authRepositoryProvider).currentSession?.accessToken,
        ),
);

/// The call for one room. Lives while the `CallControls` for that room are on
/// screen, and leaves the call when it goes away.
final callSessionProvider = Provider.autoDispose.family<CallSession, RoomId>((
  ref,
  roomId,
) {
  final session = CallSession(
    roomId: roomId,
    rooms: ref.watch(roomRepositoryProvider),
    grants: ref.watch(callGrantSourceProvider),
    call: ref.watch(callControllerProvider),
  )..start();
  ref.onDispose(session.dispose);
  return session;
});
