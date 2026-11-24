import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../rooms/data/http_room_repository.dart';
import 'demo/demo_match.dart';

/// The live room, its public table state, my private state and the match
/// result, straight from [RoomRepository]. The game UI never decides
/// anything itself: it shows these and sends actions.
final roomProvider = StreamProvider.autoDispose.family<Room, RoomId>(
  (ref, id) => ref.watch(roomRepositoryProvider).watchRoom(id),
);

final publicStateProvider = StreamProvider.autoDispose
    .family<PublicGameState, RoomId>(
      (ref, id) => ref.watch(roomRepositoryProvider).watchPublicState(id),
    );

final myStateProvider = StreamProvider.autoDispose
    .family<PrivatePlayerState, RoomId>(
      (ref, id) => ref.watch(roomRepositoryProvider).watchMyState(id),
    );

/// The room's chat as I may read it, oldest first.
final chatProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, RoomId>(
      (ref, id) => ref.watch(roomRepositoryProvider).watchChat(id),
    );

/// Refusals the server sends back on the socket, e.g. a Start with too
/// few players or a Doctor saving the same player twice.
final roomErrorsProvider = StreamProvider.autoDispose<SocketError>((ref) {
  final repo = ref.watch(roomRepositoryProvider);
  return repo is HttpRoomRepository ? repo.errors : const Stream.empty();
});

final matchEndProvider = StreamProvider.autoDispose.family<MatchResult, RoomId>(
  (ref, id) => ref.watch(roomRepositoryProvider).watchMatchEnd(id),
);

/// Whose phone this is.
final myUserIdProvider = Provider<UserId?>(
  (ref) => ref.watch(authRepositoryProvider).currentSession?.userId,
);

/// When true and the rooms service is still the fake one, a scripted
/// match plays out on the table so the screens can be tried end to end
/// before the real game server exists. Tests turn it off.
final gameDemoEnabledProvider = Provider<bool>((ref) => AppConfig.useFakes);

/// The scripted match for [roomId], or null when playing for real.
final demoMatchProvider = Provider.autoDispose.family<DemoMatch?, RoomId>((
  ref,
  roomId,
) {
  final repo = ref.watch(roomRepositoryProvider);
  if (!ref.watch(gameDemoEnabledProvider) || repo is! FakeRoomRepository) {
    return null;
  }
  final demo = DemoMatch(
    repo: repo,
    call: ref.watch(callControllerProvider),
    me: ref.watch(myUserIdProvider) ?? 'user_0',
  )..prepare();
  ref.onDispose(demo.dispose);
  return demo;
});

/// Sends player actions for one room.
final gameActionsProvider = Provider.autoDispose.family<GameActions, RoomId>(
  (ref, roomId) => GameActions(
    roomId: roomId,
    repo: ref.watch(roomRepositoryProvider),
    me: ref.watch(myUserIdProvider) ?? '',
    demo: ref.watch(demoMatchProvider(roomId)),
  ),
);

class GameActions {
  GameActions({
    required this.roomId,
    required this.repo,
    required this.me,
    this.demo,
  });

  final RoomId roomId;
  final RoomRepository repo;
  final UserId me;
  final DemoMatch? demo;

  Future<void> _send(GameAction action) async {
    await repo.send(roomId, action);
    demo?.onPlayerAction(action);
  }

  Future<void> startMatch() => _send(StartMatch(actorId: me));

  Future<void> nightAction(String type, UserId target) => _send(switch (type) {
    'nightKill' => NightKill(actorId: me, targetId: target),
    'nightHeal' => NightHeal(actorId: me, targetId: target),
    'nightCheck' => NightCheck(actorId: me, targetId: target),
    'nightGuard' => NightGuard(actorId: me, targetId: target),
    'nightSleep' => NightSleep(actorId: me, targetId: target),
    _ => throw ArgumentError.value(type, 'type', 'not a night action'),
  });

  /// [target] null means skip.
  Future<void> vote(UserId? target) =>
      _send(CastVote(actorId: me, targetId: target));

  /// Agree ([skip] true) or stop agreeing to end the timer early. The
  /// server ends it only when every living player agrees.
  Future<void> skipTimer({required bool skip}) =>
      _send(SkipPhase(actorId: me, skip: skip));

  /// A chat message; the server decides who reads it. During my last
  /// word it becomes part of that last word.
  Future<void> sendChat(String text) => repo.sendChat(roomId, text);

  /// Pops one of `ChatRules.reactions` on my seat.
  Future<void> react(String emoji) => repo.sendReaction(roomId, emoji);

  /// Host only: the roles for the next match (null: standard deal).
  Future<void> setRoles(Map<Role, int>? roleCounts) =>
      repo.setRoles(roomId, roleCounts);

  /// Host only, between matches: makes [userId] the host.
  Future<void> setHost(UserId userId) => repo.setHost(roomId, userId);

  Future<void> leave() => repo.leave(roomId);

  /// Back to the waiting room after a match: tells the server I am back
  /// for the next one. The demo just resets.
  void playAgain() {
    final d = demo;
    if (d != null) return d.reset();
    unawaited(repo.comeBack(roomId).catchError((Object _) {}));
  }
}
