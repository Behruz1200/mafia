import 'dart:async';

import '../models/account.dart';
import '../models/call.dart';
import '../models/chat.dart';
import '../models/game_action.dart';
import '../models/game_state.dart';
import '../models/ids.dart';
import '../models/match_result.dart';
import '../models/role.dart';
import '../models/room.dart';
import '../models/wallet.dart';
import '../ports/repositories.dart';
import 'fixtures.dart';

/// Signed in as `user_0` unless [signedIn] is false. Any phone code works.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({bool signedIn = true})
    : _session = signedIn ? _fakeSession() : null;

  AuthSession? _session;
  final _ctrl = StreamController<AuthSession?>.broadcast();

  static AuthSession _fakeSession() => AuthSession(
    userId: 'user_0',
    accessToken: 'fake-access',
    refreshToken: 'fake-refresh',
    expiresAt: DateTime.utc(2100),
  );

  void _set(AuthSession? s) => _ctrl.add(_session = s);

  @override
  AuthSession? get currentSession => _session;

  @override
  Stream<AuthSession?> watchSession() async* {
    yield _session;
    yield* _ctrl.stream;
  }

  @override
  Future<void> startPhoneSignIn(String phoneE164) async {}

  @override
  Future<AuthSession> verifyPhoneCode(String phoneE164, String code) async {
    _set(_fakeSession());
    return _session!;
  }

  @override
  Future<AuthSession> signInWithApple() =>
      verifyPhoneCode('+998000000000', '0000');

  @override
  Future<AuthSession> signInAsGuest() =>
      verifyPhoneCode('+998000000000', '0000');

  @override
  Future<void> signOut() async => _set(null);

  @override
  Future<void> deleteAccount() async => _set(null);
}

class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository([UserProfile? profile])
    : _profile =
          profile ??
          UserProfile(
            userId: 'user_0',
            displayName: 'Aziza',
            countryCode: 'UZ',
            isAdult: true,
            hasBirthDate: true,
            createdAt: fixtureNow,
          );

  UserProfile? _profile;
  final _ctrl = StreamController<UserProfile?>.broadcast();

  @override
  Stream<UserProfile?> watchMyProfile() async* {
    yield _profile;
    yield* _ctrl.stream;
  }

  @override
  Future<UserProfile> updateMyProfile(UserProfile profile) async {
    _ctrl.add(_profile = profile);
    return profile;
  }

  @override
  Future<UserProfile> setBirthDate(DateTime birthDate) async {
    final p = _profile!;
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    final updated = UserProfile(
      userId: p.userId,
      displayName: p.displayName,
      avatarUrl: p.avatarUrl,
      countryCode: p.countryCode,
      locale: p.locale,
      isAdult: age >= 18,
      hasBirthDate: true,
      createdAt: p.createdAt,
    );
    _ctrl.add(_profile = updated);
    return updated;
  }
}

/// A scriptable room. Tests and the UI's mock mode push state with
/// [emitRoom], [emitPublic], [emitPrivate] and [emitMatchEnd]; every action
/// sent is recorded in [sent].
class FakeRoomRepository implements RoomRepository {
  FakeRoomRepository({Room? room}) : room = room ?? sampleRoom();

  Room room;
  final sent = <GameAction>[];

  final _room = StreamController<Room>.broadcast();
  final _public = StreamController<PublicGameState>.broadcast();
  final _private = StreamController<PrivatePlayerState>.broadcast();
  final _end = StreamController<MatchResult>.broadcast();
  PublicGameState? _lastPublic;
  PrivatePlayerState? _lastPrivate;
  final chat = <ChatMessage>[];
  final _chat = StreamController<List<ChatMessage>>.broadcast();
  var _chatSeq = 0;

  final _reactions = StreamController<ChatReaction>.broadcast();

  /// Shows a reaction as if the server had sent it.
  void emitReaction(ChatReaction r) => _reactions.add(r);

  /// Shows a message as if the server had sent it.
  void emitChat(ChatMessage m) => _chat.add(List.unmodifiable(chat..add(m)));

  void emitRoom(Room r) => _room.add(room = r);
  void emitPublic(PublicGameState s) => _public.add(_lastPublic = s);
  void emitPrivate(PrivatePlayerState s) => _private.add(_lastPrivate = s);
  void emitMatchEnd(MatchResult r) => _end.add(r);

  @override
  Future<Room> createRoom(RoomSettings settings) async => room;
  @override
  Future<Room> joinByCode(InviteCode code) async => room;
  @override
  Future<Room> quickMatch() async => room;
  @override
  Future<void> leave(RoomId roomId) async {}

  @override
  Stream<Room> watchRoom(RoomId roomId) async* {
    yield room;
    yield* _room.stream;
  }

  @override
  Stream<PublicGameState> watchPublicState(RoomId roomId) async* {
    if (_lastPublic != null) yield _lastPublic!;
    yield* _public.stream;
  }

  @override
  Stream<PrivatePlayerState> watchMyState(RoomId roomId) async* {
    if (_lastPrivate != null) yield _lastPrivate!;
    yield* _private.stream;
  }

  @override
  Stream<MatchResult> watchMatchEnd(RoomId roomId) => _end.stream;

  @override
  Future<void> send(RoomId roomId, GameAction action) async => sent.add(action);

  @override
  Stream<List<ChatMessage>> watchChat(RoomId roomId) async* {
    yield List.unmodifiable(chat);
    yield* _chat.stream;
  }

  @override
  Stream<ChatReaction> watchReactions(RoomId roomId) => _reactions.stream;

  /// Echoes it back on `user_0`'s seat, like the server.
  @override
  Future<void> sendReaction(RoomId roomId, String emoji) async {
    if (!ChatRules.reactions.contains(emoji)) return;
    emitReaction(
      ChatReaction(
        roomId: roomId,
        senderId: 'user_0',
        emoji: emoji,
        channel: ChatChannel.table,
        sentAt: DateTime.now().toUtc(),
      ),
    );
  }

  /// Room ids [comeBack] was called with, for tests.
  final cameBack = <RoomId>[];

  @override
  Future<void> comeBack(RoomId roomId) async => cameBack.add(roomId);

  /// Hands the host role over at once, like the server.
  @override
  Future<void> setHost(RoomId roomId, UserId userId) async => emitRoom(
    Room(
      id: room.id,
      inviteCode: room.inviteCode,
      hostId: userId,
      status: room.status,
      settings: room.settings,
      memberIds: room.memberIds,
      memberNames: room.memberNames,
      currentMatchId: room.currentMatchId,
      createdAt: room.createdAt,
      notBackIds: room.notBackIds,
      offlineIds: room.offlineIds,
    ),
  );

  /// Applies the roles at once, like the server does for a fair setup.
  @override
  Future<void> setRoles(RoomId roomId, Map<Role, int>? roleCounts) async {
    final s = room.settings;
    emitRoom(
      Room(
        id: room.id,
        inviteCode: room.inviteCode,
        hostId: room.hostId,
        status: room.status,
        settings: RoomSettings(
          minPlayers: s.minPlayers,
          maxPlayers: s.maxPlayers,
          stake: s.stake,
          visibility: s.visibility,
          roleCounts: roleCounts,
          durations: s.durations,
        ),
        memberIds: room.memberIds,
        memberNames: room.memberNames,
        currentMatchId: room.currentMatchId,
        createdAt: room.createdAt,
      ),
    );
  }

  /// Echoes the message back on the table as `user_0`, like the server.
  @override
  Future<void> sendChat(RoomId roomId, String text) async {
    final clean = ChatRules.clean(text);
    if (clean.isEmpty) return;
    emitChat(
      ChatMessage(
        id: 'chat_${_chatSeq++}',
        roomId: roomId,
        senderId: 'user_0',
        senderName: 'You',
        text: clean,
        channel: ChatChannel.table,
        sentAt: DateTime.now().toUtc(),
      ),
    );
  }
}

/// Starts with 1,000 coins. [buy] credits instantly.
class FakeWalletRepository implements WalletRepository {
  FakeWalletRepository({int coins = 1000})
    : _balance = WalletBalance(userId: 'user_0', available: coins);

  WalletBalance _balance;
  final _ctrl = StreamController<WalletBalance>.broadcast();

  static const packs = [
    CoinPack(productId: 'coins_100', coins: 100),
    CoinPack(productId: 'coins_500', coins: 500, bonusCoins: 50),
    CoinPack(productId: 'coins_1200', coins: 1200, bonusCoins: 200),
  ];

  @override
  Stream<WalletBalance> watchBalance() async* {
    yield _balance;
    yield* _ctrl.stream;
  }

  @override
  Future<List<LedgerEntry>> history({int limit = 50}) async => const [];

  @override
  Future<List<CoinPack>> coinPacks() async => packs;

  @override
  Future<WalletBalance> buy(CoinPack pack) async {
    _balance = WalletBalance(
      userId: _balance.userId,
      available: _balance.available + pack.coins + pack.bonusCoins,
      inEscrow: _balance.inEscrow,
    );
    _ctrl.add(_balance);
    return _balance;
  }
}

/// Shows the table's players as call participants, cameras off.
class FakeCallController implements CallController {
  final _ctrl = StreamController<List<CallParticipant>>.broadcast();
  var _people = <CallParticipant>[];
  bool camera = false;
  bool mic = false;

  @override
  Stream<List<CallParticipant>> watchParticipants() async* {
    yield _people;
    yield* _ctrl.stream;
  }

  @override
  Future<void> join(CallGrant grant) async {
    _people = [
      for (final p in samplePlayers()) CallParticipant(userId: p.userId),
    ];
    _ctrl.add(_people);
  }

  @override
  Future<void> setCamera({required bool on}) async => camera = on;
  @override
  Future<void> setMic({required bool on}) async => mic = on;
  @override
  Future<void> leave() async => _ctrl.add(_people = []);
}
