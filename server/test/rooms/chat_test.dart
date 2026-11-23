import 'package:contracts/contracts.dart';
import 'package:fake_async/fake_async.dart';
import 'package:mafia_engine/mafia_engine.dart';
import 'package:server/call/call_policy.dart';
import 'package:server/rooms/match_recorder.dart';
import 'package:server/rooms/room_error.dart';
import 'package:test/test.dart';

import 'support.dart';

Matcher roomError(String code) =>
    isA<RoomError>().having((e) => e.code, 'code', code);

/// Chat and last words on the real rules: 6 players, so one Mafia, a
/// Doctor, a Detective and three civilians.
void main() {
  const users = ['u0', 'u1', 'u2', 'u3', 'u4', 'u5'];
  const settings = RoomSettings(
    minPlayers: 6,
    maxPlayers: 6,
    durations: PhaseDurations(
      roleReveal: Duration(seconds: 3),
      night: Duration(seconds: 10),
      day: Duration(seconds: 20),
      voting: Duration(seconds: 10),
      lastWord: Duration(seconds: 15),
    ),
  );

  late FakeAsync a;
  late Rig rig;
  late RoomId roomId;
  late InMemoryMatchRecorder recorder;

  void open() {
    recorder = InMemoryMatchRecorder();
    rig = Rig(engine: const MafiaEngine(), recorder: recorder);
    late Room room;
    rig.service.create('u0', settings).then((r) => room = r);
    a.flushMicrotasks();
    for (final u in users.skip(1)) {
      rig.service.join(u, room.inviteCode);
      a.flushMicrotasks();
    }
    for (final u in users) {
      rig.service.watch(rig.socket(u).conn, room.id);
    }
    a.flushMicrotasks();
    roomId = room.id;
  }

  void start() {
    rig.service.act('u0', roomId, const StartMatch(actorId: 'u0'));
    a.flushMicrotasks();
  }

  Object? say(UserId u, String text) {
    Object? err;
    rig.service
        .chat(u, roomId, text)
        .then(
          (_) {},
          onError: (Object e) {
            err = e;
          },
        );
    a.flushMicrotasks();
    return err;
  }

  /// Chat texts [u] has been sent, in order.
  List<String> seen(UserId u) => [
    for (final m in rig.sockets[u]!.messages)
      if (m is ChatPosted) m.message.text,
  ];

  List<String> history(UserId u) => [
    for (final m in rig.sockets[u]!.last<ChatHistory>()!.messages) m.text,
  ];

  PublicGameState pub() => rig.service.publicState(roomId)!;
  Role role(UserId u) => rig.service.roleOf(roomId, u)!;
  UserId first(Role r) => users.firstWhere((u) => role(u) == r);
  List<UserId> town() => [
    for (final u in users)
      if (role(u).team == Team.town) u,
  ];

  void run(void Function() body) => fakeAsync((fa) {
    a = fa;
    open();
    body();
    rig.service.dispose();
    a.flushMicrotasks();
  });

  test('in the waiting room everyone reads everyone', () {
    run(() {
      expect(say('u1', '  hello\n there  '), isNull);
      for (final u in users) {
        expect(seen(u), ['hello there']);
      }
      final m = rig.sockets['u2']!.last<ChatPosted>()!.message;
      expect(m.senderName, 'Name of u1');
      expect(m.channel, ChatChannel.table);
      expect(m.matchId, isNull);
      expect(say('u1', '   '), roomError('chat_empty'));
      expect(say('stranger', 'hi'), roomError('not_in_room'));
    });
  });

  test('too many messages too fast are refused', () {
    run(() {
      for (var i = 0; i < 5; i++) {
        expect(say('u1', 'm$i'), isNull);
      }
      expect(say('u1', 'one more'), roomError('chat_too_fast'));
      a.elapse(const Duration(seconds: 5));
      expect(say('u1', 'later'), isNull);
    });
  });

  test('at night the town is silent and the Mafia talk privately', () {
    run(() {
      start();
      a.elapse(const Duration(seconds: 3)); // night
      expect(pub().phase, GamePhase.night);
      final mafia = first(Role.mafia);
      final civ = first(Role.civilian);
      expect(say(civ, 'who is it?'), roomError('chat_closed'));
      expect(say(mafia, 'kill the doctor'), isNull);
      expect(seen(mafia), ['kill the doctor']);
      for (final u in town()) {
        expect(seen(u), isEmpty, reason: '$u must not read the Mafia');
      }
      final m = rig.sockets[mafia]!.last<ChatPosted>()!.message;
      expect(m.channel, ChatChannel.mafia);
    });
  });

  test('a killed player gets a last word, kept in the match record', () {
    run(() {
      start();
      a.elapse(const Duration(seconds: 3)); // night
      final mafia = first(Role.mafia);
      final victim = first(Role.civilian);
      rig.service.act(
        mafia,
        roomId,
        NightKill(actorId: mafia, targetId: victim),
      );
      a.elapse(const Duration(seconds: 10)); // night ends
      expect(pub().phase, GamePhase.lastWord);
      expect(pub().lastWordBy, victim);

      // Only the speaker talks: on camera and in chat.
      CallAccess access(UserId u) => CallPolicy.access(
        channel: CallChannel.table,
        userId: u,
        game: pub(),
        role: role(u),
      );
      expect(access(victim).canPublish, isTrue);
      expect(access(mafia).canPublish, isFalse);
      final other = town().firstWhere((u) => u != victim);
      expect(say(other, 'sorry'), roomError('chat_closed'));

      expect(
        say(victim, 'It was ${rig.service.displayNameOf(roomId, mafia)}'),
        isNull,
      );
      for (final u in users) {
        expect(seen(u), hasLength(1));
      }
      final m = rig.sockets[other]!.last<ChatPosted>()!.message;
      expect(m.lastWord, isTrue);
      expect(m.channel, ChatChannel.table);
      final event = pub().log.last;
      expect(event.message, EventKeys.lastWord);
      expect(event.userId, victim);
      expect(event.text, m.text);
      expect(
        recorder.actions[pub().matchId]!.whereType<SayLastWord>().single.text,
        m.text,
      );

      // The speaker can end it early; then the day starts.
      rig.service.act(victim, roomId, SkipPhase(actorId: victim));
      a.flushMicrotasks();
      expect(pub().phase, GamePhase.day);
      expect(access(victim).canPublish, isFalse);
    });
  });

  test('players who are out only reach each other', () {
    run(() {
      start();
      a.elapse(const Duration(seconds: 3)); // night
      final mafia = first(Role.mafia);
      final victim = first(Role.civilian);
      rig.service.act(
        mafia,
        roomId,
        NightKill(actorId: mafia, targetId: victim),
      );
      a.elapse(const Duration(seconds: 10)); // night ends
      a.elapse(const Duration(seconds: 15)); // last word ends
      expect(pub().phase, GamePhase.day);

      expect(say(victim, 'boo'), isNull);
      expect(seen(victim), ['boo']);
      for (final u in users.where((u) => u != victim)) {
        expect(seen(u), isEmpty, reason: '$u is alive');
      }
      expect(
        rig.sockets[victim]!.last<ChatPosted>()!.message.channel,
        ChatChannel.dead,
      );
      expect(say(mafia, 'good morning'), isNull);
      expect(seen(victim), ['boo', 'good morning']);

      // A reconnecting living player still cannot read the dead.
      final civ = town().firstWhere((u) => u != victim);
      rig.service.watch(rig.socket(civ).conn, roomId);
      a.flushMicrotasks();
      expect(history(civ), ['good morning']);
      rig.service.watch(rig.socket(victim).conn, roomId);
      a.flushMicrotasks();
      expect(history(victim), ['boo', 'good morning']);
    });
  });

  test('the Mafia night chat is dropped when the next match starts', () {
    run(() {
      start();
      a.elapse(const Duration(seconds: 3)); // night
      final mafia = first(Role.mafia);
      expect(say(mafia, 'secret'), isNull);
      // End the match: the only Mafia leaves, so the town wins.
      rig.service.leave(mafia, roomId);
      a.flushMicrotasks();
      expect(pub().phase, GamePhase.ended);
      rig.service.join(mafia, rig.service.room(roomId)!.inviteCode);
      a.flushMicrotasks();
      rig.service.watch(rig.socket(mafia).conn, roomId);
      a.flushMicrotasks();
      expect(history(mafia), ['secret'], reason: 'still their match');
      final host = rig.service.room(roomId)!.hostId;
      rig.service.act(host, roomId, StartMatch(actorId: host));
      a.flushMicrotasks();
      expect(pub().round, 0, reason: 'a new match');
      for (final u in users) {
        expect(history(u), isEmpty);
      }
    });
  });
}
