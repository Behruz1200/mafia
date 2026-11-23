import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_app/core/providers.dart';
import 'package:mafia_app/features/call/call_providers.dart';
import 'package:mafia_app/features/call/call_session.dart';
import 'package:mafia_app/features/call/call_state.dart';
import 'package:mafia_app/features/call/call_view.dart';
import 'package:mafia_app/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// Hands out grants and records what was asked. Refuses Mafia grants to
/// anyone the test has not marked as Mafia, like the server does.
class RecordingGrants implements CallGrantSource {
  RecordingGrants({this.mafiaAllowed = false, this.canPublish = true});
  bool mafiaAllowed;
  bool canPublish;
  final asked = <CallChannel>[];

  @override
  Future<CallGrant> fetch(RoomId roomId, CallChannel channel) async {
    asked.add(channel);
    if (channel == CallChannel.mafia && !mafiaAllowed) {
      throw StateError('call_not_allowed');
    }
    return CallGrant(
      serverUrl: 'wss://v',
      token: 't',
      livekitRoom: '${roomId}_${channel.name}',
      channel: channel,
      canPublish: canPublish,
      expiresAt: DateTime.utc(2100),
    );
  }
}

class FakeTableCall implements TableCallController {
  final joined = <CallGrant>[];
  final left = <CallChannel>[];
  var leftAll = false;
  LocalCallState state = const LocalCallState();
  final _local = StreamController<LocalCallState>.broadcast();
  bool? camera;
  bool? mic;
  List<CallParticipant> people = [
    for (final p in samplePlayers(4)) CallParticipant(userId: p.userId),
  ];

  void emit(LocalCallState s) => _local.add(state = s);

  @override
  LocalCallState get local => state;
  @override
  Stream<LocalCallState> watchLocal() async* {
    yield state;
    yield* _local.stream;
  }

  @override
  Stream<List<CallParticipant>> watchParticipants() => Stream.value(people);
  @override
  Future<void> join(CallGrant grant) async => joined.add(grant);
  @override
  Future<void> leaveChannel(CallChannel channel) async => left.add(channel);
  @override
  Future<void> leave() async => leftAll = true;
  @override
  Future<void> setCamera({required bool on}) async => camera = on;
  @override
  Future<void> setMic({required bool on}) async => mic = on;
}

PublicGameState phase(GamePhase p, {Set<String> dead = const {}}) {
  final s = samplePublicState(phase: p);
  return PublicGameState(
    roomId: s.roomId,
    matchId: s.matchId,
    phase: p,
    round: s.round,
    players: [
      for (final pl in s.players)
        pl.copyWith(isAlive: !dead.contains(pl.userId)),
    ],
  );
}

void main() {
  group('MediaPlan', () {
    const on = ChannelStatus(connected: true, canPublish: true);
    const muted = ChannelStatus(connected: true, canPublish: false);

    test('day: camera and mic go to the table', () {
      final p = MediaPlan.decide(
        wantCamera: true,
        wantMic: true,
        channels: {CallChannel.table: on},
      );
      expect(p.target, CallChannel.table);
      expect(p.camera && p.mic, isTrue);
    });

    test('night for the town: nothing is sent anywhere', () {
      final p = MediaPlan.decide(
        wantCamera: true,
        wantMic: true,
        channels: {CallChannel.table: muted},
      );
      expect(p.target, isNull);
      expect(p.camera || p.mic, isFalse);
    });

    test('night for Mafia: media moves to the Mafia call', () {
      final p = MediaPlan.decide(
        wantCamera: false,
        wantMic: true,
        channels: {CallChannel.table: muted, CallChannel.mafia: on},
      );
      expect(p.target, CallChannel.mafia);
      expect(p.camera, isFalse);
      expect(p.mic, isTrue);
    });
  });

  group('CallSession', () {
    late FakeRoomRepository rooms;
    late RecordingGrants grants;
    late FakeTableCall call;
    late CallSession session;

    setUp(() {
      rooms = FakeRoomRepository();
      grants = RecordingGrants();
      call = FakeTableCall();
      session = CallSession(
        roomId: 'room_1',
        rooms: rooms,
        grants: grants,
        call: call,
      )..start();
    });

    Future<void> settle() async {
      await pumpEventQueue();
      await session.idle;
    }

    test('joins the table as soon as the room opens', () async {
      await settle();
      expect(call.joined.map((g) => g.channel), [CallChannel.table]);
    });

    test('town never asks for the Mafia call', () async {
      rooms.emitPrivate(samplePrivateState());
      rooms.emitPublic(phase(GamePhase.night));
      await settle();
      expect(grants.asked, isNot(contains(CallChannel.mafia)));
    });

    test('Mafia join the Mafia call at night and leave it at dawn', () async {
      grants.mafiaAllowed = true;
      rooms.emitPrivate(samplePrivateState(role: Role.mafia));
      await settle();
      rooms.emitPublic(phase(GamePhase.night));
      await settle();
      expect(call.joined.last.channel, CallChannel.mafia);

      rooms.emitPublic(phase(GamePhase.day));
      await settle();
      expect(call.left, [CallChannel.mafia]);
      expect(call.joined.last.channel, CallChannel.table);
    });

    test('a dead Mafia player gets no Mafia call', () async {
      grants.mafiaAllowed = true;
      rooms.emitPrivate(samplePrivateState(role: Role.mafia));
      rooms.emitPublic(phase(GamePhase.night, dead: {'user_0'}));
      await settle();
      expect(grants.asked, isNot(contains(CallChannel.mafia)));
    });

    test('asks for a fresh grant at every phase change only', () async {
      await settle();
      rooms.emitPublic(phase(GamePhase.day));
      rooms.emitPublic(phase(GamePhase.day));
      await settle();
      rooms.emitPublic(phase(GamePhase.voting));
      await settle();
      expect(grants.asked, [
        CallChannel.table,
        CallChannel.table,
        CallChannel.table,
      ]);
    });

    test('leaves the call when disposed', () async {
      await settle();
      await session.dispose();
      expect(call.leftAll, isTrue);
    });
  });

  group('CallControls', () {
    Future<FakeTableCall> pump(
      WidgetTester tester, {
      required LocalCallState local,
      GamePhase? game,
    }) async {
      final call = FakeTableCall()..state = local;
      final rooms = FakeRoomRepository();
      if (game != null) rooms.emitPublic(phase(game));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            callControllerProvider.overrideWithValue(call),
            roomRepositoryProvider.overrideWithValue(rooms),
            callGrantSourceProvider.overrideWithValue(RecordingGrants()),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: CallControls(roomId: 'room_1')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return call;
    }

    IconButton button(WidgetTester tester, String key) =>
        tester.widget<IconButton>(find.byKey(ValueKey(key)));

    testWidgets('toggles camera and mic in the day', (tester) async {
      final call = await pump(
        tester,
        game: GamePhase.day,
        local: const LocalCallState(
          canPublish: true,
          connected: true,
          activeChannel: CallChannel.table,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('call-camera')));
      await tester.tap(find.byKey(const ValueKey('call-mic')));
      expect(call.camera, isTrue);
      expect(call.mic, isTrue);
      expect(call.joined.map((g) => g.channel).toSet(), {CallChannel.table});
    });

    testWidgets('at night the toggles are off and it says why', (tester) async {
      await pump(
        tester,
        game: GamePhase.night,
        local: const LocalCallState(connected: true),
      );
      expect(find.text('Night: cameras and microphones are off'), findsOne);
      expect(button(tester, 'call-camera').onPressed, isNull);
      expect(button(tester, 'call-mic').onPressed, isNull);
    });

    testWidgets('Mafia see they are in their private call', (tester) async {
      await pump(
        tester,
        game: GamePhase.night,
        local: const LocalCallState(
          connected: true,
          canPublish: true,
          activeChannel: CallChannel.mafia,
        ),
      );
      expect(
        find.text('Mafia call: only your team can see and hear you'),
        findsOne,
      );
      expect(button(tester, 'call-mic').onPressed, isNotNull);
    });

    testWidgets('in a browser that holds back sound, it asks for a tap', (
      tester,
    ) async {
      await pump(
        tester,
        game: GamePhase.day,
        local: const LocalCallState(
          connected: true,
          canPublish: true,
          activeChannel: CallChannel.table,
          audioBlocked: true,
        ),
      );
      expect(find.text('Tap here to hear the other players'), findsOne);
    });
  });

  group('SeatVideo', () {
    testWidgets('shows the placeholder while the camera is off', (
      tester,
    ) async {
      final call = FakeTableCall()
        ..people = const [CallParticipant(userId: 'user_1', isSpeaking: true)];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [callControllerProvider.overrideWithValue(call)],
          child: const MaterialApp(
            home: SizedBox(
              width: 90,
              height: 120,
              child: SeatVideo(userId: 'user_1', placeholder: Text('B')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('B'), findsOneWidget);
      // Talking: a ring around the seat.
      expect(find.byType(DecoratedBox), findsOneWidget);
    });
  });
}
