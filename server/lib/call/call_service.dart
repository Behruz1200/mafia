import 'dart:convert';

import 'package:contracts/contracts.dart';

import 'call_policy.dart';
import 'livekit_rooms.dart';
import 'livekit_token.dart';

/// What the call needs to know about one member of a room. Stream 2
/// (rooms) provides it through [CallRoomDirectory].
class CallSeat {
  const CallSeat({
    required this.roomId,
    required this.userId,
    required this.displayName,
    this.game,
    this.role,
  });

  final RoomId roomId;
  final UserId userId;
  final String displayName;

  /// The running match, or null while the room waits for players.
  final PublicGameState? game;

  /// This player's role in the running match. Server-side only.
  final Role? role;
}

/// Implemented by stream 2 (rooms). Returns null when [userId] is not a
/// member of [roomId].
abstract interface class CallRoomDirectory {
  Future<CallSeat?> seat(RoomId roomId, UserId userId);
}

/// Why a grant was refused.
class CallDenied implements Exception {
  const CallDenied(this.code);

  /// `not_in_room` or `call_not_allowed`.
  final String code;
  @override
  String toString() => 'CallDenied($code)';
}

/// LiveKit room names. One table room per game room, and one Mafia room
/// per match so old matches never share a room.
abstract final class CallRoomNames {
  static String table(RoomId roomId) => 'mafia_${roomId}_table';
  static String mafia(RoomId roomId, MatchId matchId) =>
      'mafia_${roomId}_${matchId}_night';

  static String forChannel(
    CallChannel channel,
    RoomId roomId,
    PublicGameState? game,
  ) => switch (channel) {
    CallChannel.table => table(roomId),
    CallChannel.mafia => mafia(roomId, game?.matchId ?? 'none'),
  };
}

/// Mints call grants and keeps LiveKit permissions in step with the game.
class CallService {
  CallService({
    required this.signer,
    required this.rooms,
    this.tokenTtl = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LiveKitTokenSigner signer;
  final LiveKitRooms rooms;

  /// How long a grant can be used to connect. Short, so a saved token
  /// cannot be replayed into a later night.
  final Duration tokenTtl;
  final DateTime Function() _clock;

  /// A grant for [seat] on [channel], or [CallDenied].
  CallGrant grant(CallSeat seat, CallChannel channel) {
    final access = CallPolicy.access(
      channel: channel,
      userId: seat.userId,
      game: seat.game,
      role: seat.role,
    );
    if (!access.canJoin) throw const CallDenied('call_not_allowed');
    final room = CallRoomNames.forChannel(channel, seat.roomId, seat.game);
    final token = signer.sign(
      identity: seat.userId,
      name: seat.displayName,
      metadata: jsonEncode({'roomId': seat.roomId, 'channel': channel.name}),
      ttl: tokenTtl,
      grant: VideoGrant(
        room: room,
        roomJoin: true,
        canPublish: access.canPublish,
        canSubscribe: access.canSubscribe,
        canPublishSources: const ['camera', 'microphone'],
      ),
    );
    return CallGrant(
      serverUrl: signer.credentials.publicUrl,
      token: token,
      livekitRoom: room,
      channel: channel,
      canPublish: access.canPublish,
      expiresAt: _clock().toUtc().add(tokenTtl),
    );
  }

  /// Grants every player should hold for [state], e.g. to push as
  /// `CallGrantIssued` on each player's own socket after a phase change.
  /// A Mafia grant only ever appears in that Mafia player's own list.
  Map<UserId, List<CallGrant>> grantsFor(GameState state) {
    final game = state.public;
    return {
      for (final p in game.players)
        p.userId: [
          for (final c in CallPolicy.channelsFor(
            userId: p.userId,
            game: game,
            role: state.roles[p.userId],
          ))
            grant(
              CallSeat(
                roomId: game.roomId,
                userId: p.userId,
                displayName: p.displayName,
                game: game,
                role: state.roles[p.userId],
              ),
              c,
            ),
        ],
    };
  }

  /// Call after every phase change or death. Mutes or unmutes everyone at
  /// the table, and closes the Mafia room when night ends. Tokens alone are
  /// not enough: they are only checked when someone connects.
  Future<void> syncPhase(GameState state, {GameState? previous}) async {
    final game = state.public;
    final table = CallRoomNames.table(game.roomId);
    final connected = await rooms.participants(table);
    await Future.wait([
      for (final id in connected)
        () {
          final a = CallPolicy.access(
            channel: CallChannel.table,
            userId: id,
            game: game,
            role: state.roles[id],
          );
          return rooms.setPermission(
            table,
            id,
            canPublish: a.canPublish,
            canSubscribe: a.canSubscribe,
          );
        }(),
    ]);

    // Close the Mafia room as soon as night is over, and the previous
    // match's room if a new match started.
    final prev = previous?.public;
    if (game.phase != GamePhase.night) {
      await rooms.deleteRoom(CallRoomNames.mafia(game.roomId, game.matchId));
    }
    if (prev != null && prev.matchId != game.matchId) {
      await rooms.deleteRoom(CallRoomNames.mafia(prev.roomId, prev.matchId));
    }
  }

  /// Call when a room closes for good.
  Future<void> closeRoom(RoomId roomId, {MatchId? lastMatchId}) async {
    await rooms.deleteRoom(CallRoomNames.table(roomId));
    if (lastMatchId != null) {
      await rooms.deleteRoom(CallRoomNames.mafia(roomId, lastMatchId));
    }
  }
}
