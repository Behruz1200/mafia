import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:contracts/contracts.dart';

import '../realtime/socket_handler.dart';
import '../realtime/socket_hub.dart';
import 'invite_codes.dart';
import 'match_recorder.dart';
import 'ports.dart';
import 'room_error.dart';

/// A match's full state after a change, and the state before it (null for
/// the first match in a room).
typedef MatchStateChange = ({GameState next, GameState? previous});

/// Limits and timings for rooms. The defaults suit the first server (two
/// cores, shared with another app); raise them with the hardware.
class RoomsConfig {
  const RoomsConfig({
    this.maxRooms = 200,
    this.maxStake = 10000,
    this.reconnectGrace = const Duration(seconds: 60),
    this.quickMatchSettings = const RoomSettings(
      visibility: RoomVisibility.public,
    ),
    this.quickMatchStake = 100,
    this.quickStartDelay = const Duration(seconds: 20),
    this.idleLobbyTimeout = const Duration(minutes: 30),
    this.maxMatchLength = const Duration(hours: 2),
    this.chatHistory = 100,
    this.chatBurst = 5,
    this.chatWindow = const Duration(seconds: 5),
  });

  /// Rooms open at once on this server. New rooms are refused above it.
  final int maxRooms;
  final int maxStake;

  /// How long a player may be offline before they are out: removed from a
  /// lobby, or forfeited (`PlayerLeft`) in a match.
  final Duration reconnectGrace;

  /// Settings for rooms that quick match opens. Free by default.
  final RoomSettings quickMatchSettings;

  /// Quick match puts players who may stake (adult, stake country) and can
  /// cover it into games at this stake; everyone else plays free. The two
  /// pools never mix. 100 matches the 500-coin welcome gift (5 games).
  /// 0 makes every quick match free.
  final int quickMatchStake;

  /// Public rooms start on their own this long after reaching
  /// `minPlayers`, or at once when full.
  final Duration quickStartDelay;
  final Duration idleLobbyTimeout;

  /// A match still running after this is cancelled and stakes returned.
  final Duration maxMatchLength;

  /// Chat messages kept per room (all channels), for players who reconnect.
  final int chatHistory;

  /// At most [chatBurst] chat messages per player in any [chatWindow].
  final int chatBurst;
  final Duration chatWindow;
}

class _Member {
  _Member(this.userId, this.displayName, this.avatarUrl);
  final UserId userId;
  final String displayName;
  final String? avatarUrl;
}

class _Match {
  _Match(this.id, this.state, this.players, this.stake);
  final MatchId id;
  GameState state;

  /// Everyone dealt into this match, including those who later left.
  final List<UserId> players;
  final int stake;
  int seq = 0;
  bool over = false;
  Timer? phaseTimer;
  Timer? lengthTimer;

  void cancelTimers() {
    phaseTimer?.cancel();
    lengthTimer?.cancel();
  }
}

class _LiveRoom {
  _LiveRoom({
    required this.id,
    required this.code,
    required this.hostId,
    required this.settings,
    required this.createdAt,
  });

  final RoomId id;
  final InviteCode code;
  UserId hostId;
  final RoomSettings settings;
  final DateTime createdAt;
  final members = <_Member>[];
  RoomStatus status = RoomStatus.open;
  bool starting = false;
  _Match? match;

  /// The last match's final public state, kept for late watchers.
  PublicGameState? lastPublic;

  /// The last full state sent, kept across matches so listeners always get
  /// the previous state (e.g. to close the old match's Mafia call).
  GameState? lastState;
  DateTime lastActivity = DateTime.now();
  Timer? autoStart;

  /// Recent chat on every channel, oldest first. Each player is only ever
  /// sent the messages `ChatRules` lets them read.
  final chat = <ChatMessage>[];

  bool has(UserId u) => members.any((m) => m.userId == u);
  List<UserId> get memberIds => [for (final m in members) m.userId];
  bool get isFull => members.length >= settings.maxPlayers;

  Room toRoom() => Room(
    id: id,
    inviteCode: code,
    hostId: hostId,
    status: status,
    settings: settings,
    memberIds: memberIds,
    memberNames: {for (final m in members) m.userId: m.displayName},
    currentMatchId: match?.id,
    createdAt: createdAt,
  );
}

/// Rooms, lobbies, quick match and the live matches inside them.
///
/// Everything lives in this one process. The engine decides the rules; this
/// class decides who may do what, runs the phase clock, sends each player
/// only what they may see, and moves coins at the start and end of a match.
class RoomService implements RealtimeRooms {
  RoomService({
    required this.engine,
    required this.wallet,
    required this.hub,
    this.players = const AnonymousPlayers(),
    MatchRecorder? recorder,
    RegionPolicy? regions,
    this.config = const RoomsConfig(),
    Random? random,
    DateTime Function()? now,
    void Function(String)? log,
  }) : recorder = recorder ?? InMemoryMatchRecorder(),
       regions =
           regions ??
           const RegionPolicy(launchCountries: {'UZ'}, stakeCountries: {'UZ'}),
       _random = random ?? Random.secure(),
       _now = now ?? DateTime.now,
       _log = log ?? ((m) => stderr.writeln('rooms: $m')) {
    _presenceSub = hub.presence.listen(_onPresence);
    _sweeper = Timer.periodic(const Duration(minutes: 1), (_) => _sweep());
  }

  final GameEngine engine;
  final WalletSettlement wallet;
  final SocketHub hub;
  final PlayerDirectory players;
  final MatchRecorder recorder;
  final RegionPolicy regions;
  final RoomsConfig config;
  final Random _random;
  final DateTime Function() _now;
  final void Function(String) _log;

  final _rooms = <RoomId, _LiveRoom>{};
  final _byCode = <InviteCode, RoomId>{};
  final _roomOf = <UserId, RoomId>{};
  final _offline = <UserId, Timer>{};
  final _chatTimes = <String, List<DateTime>>{};
  final _roomChanges = StreamController<Room>.broadcast();
  final _publicChanges = StreamController<PublicGameState>.broadcast();
  final _matchStates = StreamController<MatchStateChange>.broadcast();
  late final StreamSubscription<Presence> _presenceSub;
  late final Timer _sweeper;

  // ---------------------------------------------------------------- reads
  // For other server modules (video): who is in a room and what phase it
  // is in.

  /// Every change to a room's members, host or status.
  Stream<Room> get roomChanges => _roomChanges.stream;

  /// Every public state change of every match (phase, deaths, votes).
  Stream<PublicGameState> get publicChanges => _publicChanges.stream;

  /// Every full match state change, roles included, with the state before
  /// it. Server modules only (the video module mutes and moves players by
  /// role); never forward it to an app.
  Stream<MatchStateChange> get matchStates => _matchStates.stream;

  Room? room(RoomId id) => _rooms[id]?.toRoom();
  bool isMember(RoomId id, UserId u) => _rooms[id]?.has(u) ?? false;
  PublicGameState? publicState(RoomId id) {
    final r = _rooms[id];
    final live = r?.match?.state.public;
    return live != null ? _withPresence(live) : r?.lastPublic;
  }

  /// A player's role in the running match, for server modules only (the
  /// video module puts Mafia in their night call). Never send it to anyone
  /// but that player.
  Role? roleOf(RoomId id, UserId u) => _rooms[id]?.match?.state.roles[u];

  /// The name a member shows at the table, or null if not a member.
  String? displayNameOf(RoomId id, UserId u) {
    for (final m in _rooms[id]?.members ?? const <_Member>[]) {
      if (m.userId == u) return m.displayName;
    }
    return null;
  }

  int get openRooms => _rooms.length;

  // ---------------------------------------------------------------- lobby

  Future<Room> create(UserId host, RoomSettings settings) async {
    _validate(settings);
    final member = await _admit(host, settings);
    _leaveCurrentLobby(host);
    if (_rooms.length >= config.maxRooms) {
      throw const RoomError('server_busy', 503);
    }
    final r = _open(host, settings);
    _seat(r, member);
    _changed(r);
    return r.toRoom();
  }

  Future<Room> join(UserId u, String rawCode) async {
    final id = _byCode[normalizeInviteCode(rawCode)];
    final r = id == null ? null : _rooms[id];
    if (r == null) throw RoomError.notFound;
    if (r.has(u)) return r.toRoom();
    _checkJoinable(r);
    final member = await _admit(u, r.settings);
    // The room may have changed while we looked the player up.
    if (!identical(_rooms[r.id], r)) throw RoomError.notFound;
    if (r.has(u)) return r.toRoom();
    _checkJoinable(r);
    _leaveCurrentLobby(u);
    _seat(r, member);
    _changed(r);
    _maybeAutoStart(r);
    return r.toRoom();
  }

  /// Puts the player in the fullest public room they can enter, or opens a
  /// new public room with [RoomsConfig.quickMatchSettings], at
  /// [RoomsConfig.quickMatchStake] for players who can stake, else free.
  Future<Room> quickMatch(UserId u) async {
    final current = _roomOf[u];
    if (current != null) {
      final r = _rooms[current]!;
      if (r.settings.visibility == RoomVisibility.public &&
          r.status == RoomStatus.open) {
        return r.toRoom();
      }
    }
    final profile = await players.profile(u);
    final want = config.quickMatchStake;
    final stake =
        want > 0 &&
            _stakesAllowed(profile) &&
            (await wallet.balance(u)).canAfford(want)
        ? want
        : 0;
    final candidates =
        _rooms.values
            .where(
              (r) =>
                  r.settings.visibility == RoomVisibility.public &&
                  r.status == RoomStatus.open &&
                  !r.starting &&
                  !r.isFull &&
                  !r.has(u) &&
                  r.settings.stake == stake,
            )
            .toList()
          ..sort((a, b) {
            final byCount = b.members.length.compareTo(a.members.length);
            return byCount != 0 ? byCount : a.createdAt.compareTo(b.createdAt);
          });
    for (final r in candidates) {
      try {
        return await join(u, r.code);
      } on RoomError {
        continue; // filled up or started meanwhile; try the next one
      }
    }
    final q = config.quickMatchSettings;
    return create(
      u,
      RoomSettings(
        minPlayers: q.minPlayers,
        maxPlayers: q.maxPlayers,
        stake: stake,
        visibility: RoomVisibility.public,
        roleCounts: q.roleCounts,
        durations: q.durations,
      ),
    );
  }

  Room get(UserId u, RoomId id) {
    final r = _rooms[id];
    if (r == null || !r.has(u)) throw RoomError.notFound;
    return r.toRoom();
  }

  /// Leaving a match forfeits the stake.
  Future<void> leave(UserId u, RoomId id) async {
    final r = _rooms[id];
    if (r == null || !r.has(u)) return;
    if (r.starting) throw RoomError.inMatch;
    final m = r.match;
    if (m != null && !m.over && m.players.contains(u)) {
      _systemAction(r, PlayerLeft(userId: u));
    }
    _remove(r, u);
  }

  // ------------------------------------------------------------- realtime

  @override
  Future<void> watch(ClientConnection c, RoomId roomId) async {
    final r = _rooms[roomId];
    if (r == null || !r.has(c.userId)) throw RoomError.notMember;
    c.watching.add(roomId);
    c.send(RoomUpdated(r.toRoom()));
    final m = r.match;
    if (m != null) {
      c.send(PublicStateUpdated(_withPresence(m.state.public)));
      final mine = _privateFor(m, c.userId);
      if (mine != null) c.send(PrivateStateUpdated(roomId, mine));
    } else if (r.lastPublic != null) {
      c.send(PublicStateUpdated(r.lastPublic!));
    }
    c.send(ChatHistory(roomId, _chatFor(r, c.userId)));
  }

  @override
  void unwatch(ClientConnection c, RoomId roomId) => c.watching.remove(roomId);

  @override
  Future<void> act(UserId u, RoomId roomId, GameAction action) async {
    final r = _rooms[roomId];
    if (r == null || !r.has(u)) throw RoomError.notMember;
    r.lastActivity = _now();
    if (action is StartMatch) {
      if (r.hostId != u) throw RoomError.notHost;
      return _start(r);
    }
    final m = r.match;
    if (m == null || m.over) throw const RoomError('wrong_phase', 400);
    if (!m.players.contains(u)) throw RoomError.notMember;
    _apply(r, action, fromPlayer: true);
  }

  // ----------------------------------------------------------------- chat

  /// A chat message. Who may write and who reads it follows `ChatRules`
  /// (the same secrecy as the camera and mic). During their last word, the
  /// speaker's messages are also fed to the engine as `SayLastWord`, so the
  /// last word is kept in the match log and the match record.
  @override
  Future<void> chat(UserId u, RoomId roomId, String raw) async {
    final r = _rooms[roomId];
    if (r == null || !r.has(u)) throw RoomError.notMember;
    final text = ChatRules.clean(raw);
    if (text.isEmpty) throw const RoomError('chat_empty', 400);
    final live = r.match != null && !r.match!.over ? r.match : null;
    final pub = live?.state.public;
    final speaker = pub?.phase == GamePhase.lastWord && pub?.lastWordBy == u;
    final channel = _channelOf(r, u);
    if (channel == null) throw const RoomError('chat_closed', 400);
    _checkChatRate(u);
    if (speaker) {
      _apply(r, SayLastWord(actorId: u, text: text), fromPlayer: true);
    }
    r.lastActivity = _now();
    final msg = ChatMessage(
      id: _id('c'),
      roomId: r.id,
      matchId: live?.id,
      senderId: u,
      senderName: displayNameOf(r.id, u) ?? '',
      text: text,
      channel: channel,
      sentAt: _now(),
      lastWord: speaker,
    );
    r.chat.add(msg);
    if (r.chat.length > config.chatHistory) {
      r.chat.removeRange(0, r.chat.length - config.chatHistory);
    }
    for (final v in {...r.memberIds, ...?live?.players}) {
      if (_canRead(r, v, msg)) hub.sendToUser(v, ChatPosted(msg), room: r.id);
    }
  }

  /// An emoji on [u]'s seat. It reaches exactly the players a chat message
  /// from [u] would reach right now, and is not kept.
  @override
  Future<void> react(UserId u, RoomId roomId, String emoji) async {
    final r = _rooms[roomId];
    if (r == null || !r.has(u)) throw RoomError.notMember;
    if (!ChatRules.reactions.contains(emoji)) throw RoomError.badRequest;
    final channel = _channelOf(r, u);
    if (channel == null) throw const RoomError('chat_closed', 400);
    _checkChatRate('react:$u');
    final live = r.match != null && !r.match!.over ? r.match : null;
    final reaction = ChatReaction(
      roomId: r.id,
      senderId: u,
      emoji: emoji,
      channel: channel,
      sentAt: _now(),
    );
    // Checked like a message of this match, so the same readers see it.
    final probe = ChatMessage(
      id: '',
      roomId: r.id,
      matchId: live?.id,
      senderId: u,
      senderName: '',
      text: '',
      channel: channel,
      sentAt: reaction.sentAt,
    );
    for (final v in {...r.memberIds, ...?live?.players}) {
      if (_canRead(r, v, probe)) {
        hub.sendToUser(v, ReactionShown(reaction), room: r.id);
      }
    }
  }

  /// Where a message from [u] goes right now (`ChatRules.channelFor`), or
  /// null when they may not write.
  ChatChannel? _channelOf(_LiveRoom r, UserId u) {
    final live = r.match != null && !r.match!.over ? r.match : null;
    final pub = live?.state.public;
    final me = pub?.players.where((p) => p.userId == u).firstOrNull;
    return ChatRules.channelFor(
      phase: pub?.phase,
      inMatch: me != null,
      isAlive: me?.isAlive ?? false,
      role: live?.state.roles[u],
      isLastWordSpeaker:
          pub?.phase == GamePhase.lastWord && pub?.lastWordBy == u,
    );
  }

  void _checkChatRate(String u) {
    final now = _now();
    final times = (_chatTimes[u] ??= [])
      ..removeWhere((t) => now.difference(t) >= config.chatWindow);
    if (times.length >= config.chatBurst) {
      throw const RoomError('chat_too_fast', 429);
    }
    times.add(now);
  }

  /// Whether [viewer] may read [msg]: table messages always; Mafia and
  /// dead-player messages only within their own match, by its rules.
  bool _canRead(_LiveRoom r, UserId viewer, ChatMessage msg) {
    if (msg.channel == ChatChannel.table) return true;
    final state = r.match?.state ?? r.lastState;
    if (state == null || state.public.matchId != msg.matchId) return false;
    final p = state.public.players.where((p) => p.userId == viewer);
    return ChatRules.canRead(
      channel: msg.channel,
      inMatch: p.isNotEmpty,
      isAlive: p.firstOrNull?.isAlive ?? false,
      role: state.roles[viewer],
    );
  }

  List<ChatMessage> _chatFor(_LiveRoom r, UserId u) => [
    for (final m in r.chat)
      if (_canRead(r, u, m)) m,
  ];

  void _sendChatHistory(_LiveRoom r, Iterable<UserId> users) {
    for (final u in users) {
      hub.sendToUser(u, ChatHistory(r.id, _chatFor(r, u)), room: r.id);
    }
  }

  // ---------------------------------------------------------------- match

  Future<void> _start(_LiveRoom r) async {
    if (r.status != RoomStatus.open || r.starting) throw RoomError.inMatch;
    if (r.members.length < r.settings.minPlayers) {
      throw RoomError.notEnoughPlayers;
    }
    r.autoStart?.cancel();
    r.starting = true;
    final matchId = _id('m');
    final seed = _random.nextInt(1 << 32);
    final seated = [...r.members];
    final ids = [for (final m in seated) m.userId];
    final stake = r.settings.stake;
    final at = _now();
    try {
      await recorder.started(
        roomId: r.id,
        matchId: matchId,
        stake: stake,
        players: ids,
        seed: seed,
        at: at,
      );
      if (stake > 0) {
        await wallet.holdStakes(matchId: matchId, players: ids, stake: stake);
      }
    } on InsufficientCoins catch (e) {
      r.starting = false;
      await _settleWithRetry(_cancelled(r.id, matchId, stake));
      _onShortOfCoins(r, e.userIds);
      throw RoomError(
        RoomError.insufficientCoins.code,
        RoomError.insufficientCoins.status,
        e.userIds.join(','),
      );
    } on Object catch (e) {
      r.starting = false;
      _log('match $matchId could not start: $e');
      unawaited(_settleWithRetry(_cancelled(r.id, matchId, stake)));
      throw const RoomError('server_error', 500);
    }

    final GameState state;
    try {
      state = engine.newMatch(
        roomId: r.id,
        matchId: matchId,
        players: [
          for (final (i, m) in seated.indexed)
            Player(
              userId: m.userId,
              displayName: m.displayName,
              avatarUrl: m.avatarUrl,
              seat: i,
              isHost: m.userId == r.hostId,
            ),
        ],
        settings: r.settings,
        seed: seed,
        now: at,
      );
    } on Object catch (e) {
      r.starting = false;
      _log('engine could not deal match $matchId: $e');
      unawaited(_settleWithRetry(_cancelled(r.id, matchId, stake)));
      throw const RoomError('server_error', 500);
    }

    final m = _Match(matchId, state, ids, stake);
    r
      ..starting = false
      ..match = m
      ..lastPublic = null
      ..status = RoomStatus.inMatch;
    m.lengthTimer = Timer(config.maxMatchLength, () {
      _log('match $matchId ran too long; cancelling');
      _finish(r, m, _cancelled(r.id, matchId, stake));
    });
    // The last match's secret chats are over; table chat carries on.
    r.chat.removeWhere((c) => c.channel != ChatChannel.table);
    _changed(r);
    _broadcast(r, m);
    _sendChatHistory(r, r.memberIds);
    _scheduleTimeout(r, m);
    if (stake > 0) _sendBalances(ids);
    // Anyone who dropped while the match was starting gets their grace now.
    for (final u in ids) {
      if (!hub.isOnline(u)) _onPresence((userId: u, online: false));
    }
  }

  void _apply(_LiveRoom r, GameAction action, {bool fromPlayer = false}) {
    final m = r.match;
    if (m == null || m.over) return;
    final ApplyResult result;
    try {
      result = engine.apply(m.state, action, now: _now());
    } on Object catch (e) {
      _log('engine failed on ${action.type} in ${m.id}: $e');
      if (fromPlayer) throw const RoomError('server_error', 500);
      // A broken clock tick would freeze the match: cancel and refund.
      _finish(r, m, _cancelled(r.id, m.id, m.stake));
      return;
    }
    switch (result) {
      case Rejected(:final code):
        if (fromPlayer) throw RoomError(code, 400);
        if (action is PhaseTimeout) _scheduleTimeout(r, m);
      case Accepted(:final state, :final matchResult):
        m.state = state;
        unawaited(
          _quietly(() => recorder.action(m.id, m.seq++, action, _now())),
        );
        _broadcast(r, m);
        if (matchResult != null) {
          _finish(r, m, matchResult);
        } else {
          _scheduleTimeout(r, m);
        }
    }
  }

  void _systemAction(_LiveRoom r, GameAction a) => _apply(r, a);

  void _scheduleTimeout(_LiveRoom r, _Match m) {
    m.phaseTimer?.cancel();
    final ends = m.state.public.phaseEndsAt;
    if (ends == null || m.over) return;
    var wait = ends.difference(_now());
    if (wait.isNegative) wait = Duration.zero;
    final phase = m.state.public.phase;
    final round = m.state.public.round;
    m.phaseTimer = Timer(wait, () {
      final p = m.state.public;
      if (m.over || p.phase != phase || p.round != round) return;
      _systemAction(r, const PhaseTimeout());
    });
  }

  void _finish(_LiveRoom r, _Match m, MatchResult result) {
    if (m.over) return;
    m
      ..over = true
      ..cancelTimers();
    r
      ..lastPublic = _withPresence(m.state.public)
      ..match = null
      ..status = RoomStatus.open
      ..lastActivity = _now();
    hub.sendToRoom(r.id, {...r.memberIds, ...m.players}, MatchEnded(result));
    // Players who dropped out for good leave the room with the match.
    for (final u in [...r.memberIds]) {
      if (!hub.isOnline(u) && !_offline.containsKey(u)) _remove(r, u);
    }
    if (r.members.isEmpty) {
      _close(r);
    } else if (_rooms.containsKey(r.id)) {
      _changed(r);
    }
    unawaited(
      _quietly(() => recorder.ended(result)).then((_) async {
        await _settleWithRetry(result);
        if (m.stake > 0) _sendBalances(m.players);
      }),
    );
  }

  MatchResult _cancelled(RoomId room, MatchId match, int stake) => MatchResult(
    roomId: room,
    matchId: match,
    stake: stake,
    winners: const [],
    losers: const [],
    endedAt: _now(),
  );

  /// Settlement is idempotent per match, so retrying is always safe. If it
  /// still fails, the match stays unsettled and [recoverUnsettled] picks it
  /// up on the next start.
  Future<bool> _settleWithRetry(MatchResult result, {int attempts = 5}) async {
    for (var i = 0; i < attempts; i++) {
      try {
        await wallet.settle(result);
        await _quietly(() => recorder.settled(result.matchId, _now()));
        return true;
      } on Object catch (e) {
        _log('settle ${result.matchId} failed (try ${i + 1}): $e');
        await Future<void>.delayed(Duration(seconds: 1 << i));
      }
    }
    return false;
  }

  /// Run at server start: settles every match the last process left open,
  /// paying out finished ones and refunding the rest.
  Future<int> recoverUnsettled() async {
    var n = 0;
    for (final u in await recorder.unsettled()) {
      if (_rooms.values.any((r) => r.match?.id == u.matchId)) continue;
      final result = u.resultOrCancelled(_now());
      _log('recovering ${u.matchId}: ${result.cancelled ? 'refund' : 'pay'}');
      if (await _settleWithRetry(result, attempts: 3)) n++;
    }
    return n;
  }

  // ------------------------------------------------------------- sending

  void _broadcast(_LiveRoom r, _Match m) {
    final public = _withPresence(m.state.public);
    final watchers = {...r.memberIds, ...m.players};
    hub.sendToRoom(r.id, watchers, PublicStateUpdated(public));
    for (final u in m.players) {
      if (!r.has(u)) continue;
      final mine = _privateFor(m, u);
      if (mine != null) {
        hub.sendToUser(u, PrivateStateUpdated(r.id, mine), room: r.id);
      }
    }
    _publicChanges.add(public);
    final full = GameState(
      public: public,
      roles: m.state.roles,
      settings: m.state.settings,
      pendingNightActions: m.state.pendingNightActions,
      seed: m.state.seed,
    );
    final previous = r.lastState;
    _matchStates.add((next: full, previous: previous));
    r.lastState = full;
    // Players just eliminated can now read the dead players' chat.
    if (previous != null && previous.public.matchId == public.matchId) {
      final wasAlive = {
        for (final p in previous.public.players)
          if (p.isAlive) p.userId,
      };
      final newlyOut = [
        for (final p in public.players)
          if (!p.isAlive && wasAlive.contains(p.userId)) p.userId,
      ];
      if (newlyOut.isNotEmpty) _sendChatHistory(r, newlyOut);
    }
  }

  PrivatePlayerState? _privateFor(_Match m, UserId u) {
    if (!m.state.roles.containsKey(u)) return null;
    try {
      return engine.privateView(m.state, u);
    } on Object catch (e) {
      _log('privateView failed for $u in ${m.id}: $e');
      return null;
    }
  }

  PublicGameState _withPresence(PublicGameState s) => PublicGameState(
    roomId: s.roomId,
    matchId: s.matchId,
    phase: s.phase,
    round: s.round,
    phaseEndsAt: s.phaseEndsAt,
    players: [
      for (final p in s.players)
        p.copyWith(isConnected: hub.isOnline(p.userId)),
    ],
    votes: s.votes,
    skipVotes: s.skipVotes,
    log: s.log,
    winner: s.winner,
    lastWordBy: s.lastWordBy,
  );

  void _sendBalances(Iterable<UserId> users) {
    for (final u in users) {
      unawaited(
        _quietly(
          () async => hub.sendToUser(u, WalletUpdated(await wallet.balance(u))),
        ),
      );
    }
  }

  void _changed(_LiveRoom r) {
    final room = r.toRoom();
    hub.sendToRoom(r.id, r.memberIds, RoomUpdated(room));
    _roomChanges.add(room);
  }

  // --------------------------------------------------------- membership

  void _validate(RoomSettings s) {
    final d = s.durations;
    bool okSec(Duration x, int lo, int hi) =>
        x.inSeconds >= lo && x.inSeconds <= hi;
    final ok =
        s.minPlayers >= 4 &&
        s.maxPlayers <= 12 &&
        s.minPlayers <= s.maxPlayers &&
        s.stake >= 0 &&
        s.stake <= config.maxStake &&
        (s.roleCounts?.values.every((n) => n >= 0) ?? true) &&
        okSec(d.roleReveal, 3, 60) &&
        okSec(d.night, 10, 180) &&
        okSec(d.day, 20, 600) &&
        okSec(d.voting, 10, 180) &&
        okSec(d.lastWord, 10, 120);
    if (!ok) throw const RoomError('invalid_settings', 400);
  }

  bool _stakesAllowed(UserProfile? p) =>
      p != null &&
      regions.allowsStakes(country: p.countryCode, isAdult: p.isAdult);

  /// Checks the player may sit in a room with these settings, and gets the
  /// name shown at the table.
  Future<_Member> _admit(UserId u, RoomSettings s) async {
    final current = _roomOf[u];
    if (current != null) {
      final r = _rooms[current];
      if (r != null && (r.starting || r.status == RoomStatus.inMatch)) {
        throw RoomError.alreadyPlaying;
      }
    }
    final profile = await players.profile(u);
    if (s.stake > 0) {
      if (!_stakesAllowed(profile)) throw RoomError.stakesNotAllowed;
      if (!(await wallet.balance(u)).canAfford(s.stake)) {
        throw RoomError.insufficientCoins;
      }
    }
    return _Member(
      u,
      profile?.displayName ??
          'Player ${u.length > 4 ? u.substring(u.length - 4) : u}',
      profile?.avatarUrl,
    );
  }

  void _checkJoinable(_LiveRoom r) {
    if (r.status != RoomStatus.open || r.starting) throw RoomError.inMatch;
    if (r.isFull) throw RoomError.full;
  }

  _LiveRoom _open(UserId host, RoomSettings s) {
    String code;
    do {
      code = newInviteCode(_random);
    } while (_byCode.containsKey(code));
    final r = _LiveRoom(
      id: _id('r'),
      code: code,
      hostId: host,
      settings: s,
      createdAt: _now(),
    )..lastActivity = _now();
    _rooms[r.id] = r;
    _byCode[code] = r.id;
    return r;
  }

  void _seat(_LiveRoom r, _Member m) {
    r.members.add(m);
    r.lastActivity = _now();
    _roomOf[m.userId] = r.id;
  }

  void _leaveCurrentLobby(UserId u) {
    final id = _roomOf[u];
    final r = id == null ? null : _rooms[id];
    if (r != null && r.status == RoomStatus.open && !r.starting) _remove(r, u);
  }

  void _remove(_LiveRoom r, UserId u) {
    r.members.removeWhere((m) => m.userId == u);
    if (_roomOf[u] == r.id) _roomOf.remove(u);
    _offline.remove(u)?.cancel();
    // Tell the player's sockets they are out; nothing more is sent to them.
    hub.sendToUser(u, RoomUpdated(r.toRoom()), room: r.id);
    if (r.members.isEmpty && (r.match == null || r.match!.over)) {
      _close(r);
      return;
    }
    if (r.hostId == u && r.members.isNotEmpty) {
      r.hostId = r.members.first.userId;
    }
    if (r.members.length < r.settings.minPlayers) r.autoStart?.cancel();
    _changed(r);
  }

  void _close(_LiveRoom r) {
    r.autoStart?.cancel();
    r.match?.cancelTimers();
    _rooms.remove(r.id);
    _byCode.remove(r.code);
    for (final m in r.members) {
      if (_roomOf[m.userId] == r.id) _roomOf.remove(m.userId);
    }
    _roomChanges.add(
      Room(
        id: r.id,
        inviteCode: r.code,
        hostId: r.hostId,
        status: RoomStatus.closed,
        settings: r.settings,
        memberIds: const [],
        createdAt: r.createdAt,
      ),
    );
  }

  void _maybeAutoStart(_LiveRoom r) {
    if (r.settings.visibility != RoomVisibility.public) return;
    if (r.members.length < r.settings.minPlayers) return;
    void go() => unawaited(_quietly(() => _start(r)));
    r.autoStart?.cancel();
    if (r.isFull) {
      go();
    } else {
      r.autoStart = Timer(config.quickStartDelay, go);
    }
  }

  /// In a public room, players who cannot cover the stake are moved out so
  /// the others can still play. Private rooms keep everyone; the host sees
  /// the error and can sort it out.
  void _onShortOfCoins(_LiveRoom r, List<UserId> short) {
    if (r.settings.visibility != RoomVisibility.public) return;
    for (final u in short) {
      if (!r.has(u)) continue;
      hub.sendToUser(u, const SocketError('insufficient_coins'));
      _remove(r, u);
    }
  }

  void _onPresence(Presence p) {
    final id = _roomOf[p.userId];
    final r = id == null ? null : _rooms[id];
    if (p.online) {
      _offline.remove(p.userId)?.cancel();
      final m = r?.match;
      if (r != null && m != null) _broadcast(r, m);
      return;
    }
    if (r == null) return;
    final m = r.match;
    if (m != null) _broadcast(r, m);
    _offline[p.userId]?.cancel();
    _offline[p.userId] = Timer(config.reconnectGrace, () {
      _offline.remove(p.userId);
      final now = _rooms[r.id];
      if (now == null || !now.has(p.userId) || hub.isOnline(p.userId)) return;
      if (now.starting) return;
      final m = now.match;
      if (m != null && !m.over) {
        // Out of the match (stake forfeited) but still seated, so they see
        // the result if they come back before it ends.
        _systemAction(now, PlayerLeft(userId: p.userId));
      } else {
        _remove(now, p.userId);
      }
    });
  }

  void _sweep() {
    final now = _now();
    _chatTimes.removeWhere(
      (_, t) => t.isEmpty || now.difference(t.last) >= config.chatWindow,
    );
    for (final r in [..._rooms.values]) {
      if (r.status != RoomStatus.open || r.starting) continue;
      if (r.members.isEmpty) {
        _close(r);
      } else if (now.difference(r.lastActivity) > config.idleLobbyTimeout) {
        _log('closing idle room ${r.id}');
        for (final u in [...r.memberIds]) {
          _remove(r, u);
        }
      }
    }
  }

  String _id(String prefix) {
    final b = StringBuffer('${prefix}_');
    for (var i = 0; i < 16; i++) {
      b.write(_random.nextInt(16).toRadixString(16));
    }
    return b.toString();
  }

  Future<void> _quietly(Future<void> Function() f) async {
    try {
      await f();
    } on Object catch (e) {
      _log('background task failed: $e');
    }
  }

  Future<void> dispose() async {
    _sweeper.cancel();
    await _presenceSub.cancel();
    for (final t in _offline.values) {
      t.cancel();
    }
    for (final r in _rooms.values) {
      r.autoStart?.cancel();
      r.match?.cancelTimers();
    }
  }
}
