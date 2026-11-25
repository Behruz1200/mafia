import 'package:contracts/contracts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../core/theme.dart';
import '../../call/call_view.dart';
import '../ui/game_style.dart';
import '../shot/frozen_frame.dart';
import '../shot/last_frame_keeper.dart';
import '../shot/shot_panel.dart';
import '../ui/game_text.dart';
import 'chat_panel.dart';
import 'phase_header.dart';
import 'player_table.dart';
import 'vote_board.dart';
import 'role_card.dart';
import 'skip_timer_bar.dart';

/// The table during a match: night, day, voting and last words.
///
/// Holds only what the player is picking right now. Everything else comes
/// from the server's states; the buttons shown follow
/// [PrivatePlayerState.allowedActions].
class MatchView extends StatefulWidget {
  const MatchView({
    super.key,
    required this.roomId,
    required this.state,
    required this.me,
    required this.private,
    required this.onNightAction,
    required this.onVote,
    this.onSkipTimer,
    this.refusals = 0,
  });

  final RoomId roomId;
  final PublicGameState state;
  final UserId? me;
  final PrivatePlayerState? private;
  final Future<void> Function(String type, UserId target) onNightAction;
  final Future<void> Function(UserId? target) onVote;

  /// Agree or stop agreeing to end the day's timer early.
  final Future<void> Function(bool skip)? onSkipTimer;

  /// Goes up each time the server refuses one of this player's actions,
  /// so a pick shown as confirmed can be made again.
  final int refusals;

  @override
  State<MatchView> createState() => _MatchViewState();
}

class _MatchViewState extends State<MatchView> {
  UserId? _selected;
  bool _sending = false;

  /// What the server already has from this player this turn, per action:
  /// a target id, or '' for a skipped vote. The same choice can't be sent
  /// twice; picking someone else and confirming again changes it (the
  /// rules allow that).
  final _done = <String, String>{};

  /// The Don's pick between shooting and checking; null before they chose.
  String? _donMode;

  /// The current turn; the pick is cleared whenever it changes.
  String get _turn =>
      '${widget.state.matchId}/${widget.state.round}/${widget.state.phase.name}';
  late String _lastTurn = _turn;

  List<String> get _allowed => widget.private?.allowedActions ?? const [];

  /// The Don may both shoot and look for the Detective at night.
  bool get _donChoice =>
      _allowed.contains('nightKill') && _allowed.contains('nightCheck');

  /// The one action this player is picking for now, if any.
  String? get _action {
    if (_donChoice) {
      return _donMode ??
          (_done.containsKey('nightKill') ? 'nightCheck' : 'nightKill');
    }
    const order = [
      'nightKill',
      'nightHeal',
      'nightCheck',
      'nightGuard',
      'nightSleep',
      'castVote',
    ];
    for (final a in order) {
      if (_allowed.contains(a)) return a;
    }
    return null;
  }

  /// Players whose comic panel is playing: their last word just ended and
  /// they were shot or voted out.
  final _playing = <({UserId id, OutKind kind})>[];

  @override
  void didUpdateWidget(MatchView old) {
    super.didUpdateWidget(old);
    // The server said no: nothing counts as sent any more.
    if (widget.refusals != old.refusals) _done.clear();
    final s = widget.state;
    if (s.matchId != old.state.matchId) {
      _playing.clear();
      return;
    }
    // A last word just ended: freeze that player's picture and play the
    // shot (or the vote stamp) once.
    final was = old.state.phase == GamePhase.lastWord
        ? old.state.lastWordBy
        : null;
    if (was != null &&
        (s.phase != GamePhase.lastWord || s.lastWordBy != was) &&
        !_playing.any((p) => p.id == was) &&
        !MediaQuery.disableAnimationsOf(context)) {
      final kind = switch (outCause(s, was)) {
        EliminationCause.killedAtNight => OutKind.shot,
        EliminationCause.votedOut => OutKind.votedOut,
        _ => null,
      };
      if (kind != null) _playing.add((id: was, kind: kind));
    }
  }

  Set<UserId> _targets(String? action) {
    final me = widget.me;
    final mates = widget.private?.teammates ?? const [];
    final checks = {
      ...?widget.private?.checks,
      ...?widget.private?.detectiveChecks,
    };
    final alive = widget.state.alive.map((p) => p.userId);
    return switch (action) {
      'nightKill' => {
        for (final u in alive)
          if (u != me && !mates.contains(u)) u,
      },
      'nightHeal' => alive.toSet(),
      'nightGuard' || 'nightSleep' => {
        for (final u in alive)
          if (u != me) u,
      },
      'nightCheck' => {
        for (final u in alive)
          if (u != me && !mates.contains(u) && !checks.containsKey(u)) u,
      },
      'castVote' => {
        for (final u in alive)
          if (u != me) u,
      },
      _ => const {},
    };
  }

  String _name(UserId id) =>
      widget.state.players
          .where((p) => p.userId == id)
          .map((p) => p.displayName)
          .firstOrNull ??
      '…';

  bool get _meAlive =>
      widget.state.players.any((p) => p.userId == widget.me && p.isAlive);

  Future<void> _confirm(String action, {bool skip = false}) async {
    if (_sending) return;
    final choice = skip ? '' : _selected!;
    setState(() => _sending = true);
    try {
      if (action == 'castVote') {
        await widget.onVote(skip ? null : choice);
      } else {
        await widget.onNightAction(action, choice);
      }
      if (mounted && _turn == _lastTurn) {
        setState(() {
          _done[action] = choice;
          // The Don goes on to the check once the shot is in.
          if (_donChoice &&
              action == 'nightKill' &&
              !_done.containsKey('nightCheck')) {
            _donMode = 'nightCheck';
            _selected = null;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).lobbyError)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    if (_turn != _lastTurn) {
      _lastTurn = _turn;
      _selected = null;
      _done.clear();
      _donMode = null;
    }
    final s = widget.state;
    final action = _action;
    final targets = _targets(action);
    if (_selected != null && !targets.contains(_selected)) _selected = null;
    final role = widget.private?.role;
    final isNight = s.phase == GamePhase.night;
    final events = [for (final e in s.log.reversed) ?t.eventText(e, _name)];

    final sleeping = isNight && action == null && _meAlive;
    final canSkip =
        widget.onSkipTimer != null &&
        (widget.private?.allowedActions ?? const []).contains('skipPhase');
    final lastWord = s.phase == GamePhase.lastWord;
    final speaker = lastWord ? s.lastWordBy : null;
    final iSpeak = speaker != null && speaker == widget.me;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            spacing: 10,
            children: [
              Expanded(child: PhaseHeader(state: s)),
              if (role != null)
                RolePeekButton(
                  role: role,
                  teammateNames: [
                    for (final m in widget.private!.teammates) _name(m),
                  ],
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              if (speaker != null) ...[
                LastFrameKeeper(
                  key: ValueKey('keep-${s.matchId}-$speaker'),
                  matchId: s.matchId,
                  userId: speaker,
                ),
                _LastWordStage(
                  name: iSpeak ? t.gameYou : _name(speaker),
                  lines: [
                    for (final e in s.log)
                      if (e.message == 'lastWord' &&
                          e.userId == speaker &&
                          e.text != null)
                        e.text!,
                  ],
                ),
                const SizedBox(height: 12),
              ],
              SeatReactions(
                roomId: widget.roomId,
                builder: (context, showing) => PlayerTable(
                  players: s.players,
                  me: widget.me,
                  private: widget.private,
                  votes: s.phase == GamePhase.voting ? s.votes : const {},
                  selectable: _sending ? const {} : targets,
                  selected: _selected,
                  onSelect: (u) => setState(() => _selected = u),
                  // Stream 3 (video) owns SeatVideo: each seat is that
                  // player's camera.
                  face: (id, placeholder) =>
                      SeatVideo(userId: id, placeholder: placeholder),
                  overlays: {
                    for (final e in showing.entries)
                      e.key: ReactionPop(emoji: e.value),
                  },
                  highlight: speaker,
                  outFace: (id, placeholder) {
                    // Their last word just ended: the shot plays right on
                    // their seat, then the seat keeps the grey comic.
                    final playing = _playing.where((p) => p.id == id);
                    if (playing.isNotEmpty) {
                      final p = playing.first;
                      return Consumer(
                        key: ValueKey('shot-$id'),
                        builder: (context, ref, _) {
                          ref.watch(frozenFramesProvider);
                          return ShotPanel(
                            kind: p.kind,
                            name: _name(id),
                            frame: ref
                                .read(frozenFramesProvider.notifier)
                                .forMatch(s.matchId)[id],
                            onDone: () => setState(
                              () => _playing.removeWhere((q) => q.id == id),
                            ),
                          );
                        },
                      );
                    }
                    final cause = outCause(s, id);
                    if (cause != EliminationCause.killedAtNight &&
                        cause != EliminationCause.votedOut) {
                      return null;
                    }
                    return Consumer(
                      builder: (context, ref, _) {
                        ref.watch(frozenFramesProvider);
                        return ComicOutFace(
                          frame: ref
                              .read(frozenFramesProvider.notifier)
                              .forMatch(s.matchId)[id],
                          fallback: placeholder,
                          shot: cause == EliminationCause.killedAtNight,
                          label: t.shotSeatOut,
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              _Prompt(
                text: _promptText(t, action),
                latest: events.firstOrNull,
                icon: lastWord
                    ? Icons.record_voice_over_rounded
                    : !_meAlive
                    ? Icons.visibility_rounded
                    : sleeping
                    ? Icons.bedtime_rounded
                    : action != null
                    ? Icons.touch_app_rounded
                    : Icons.forum_rounded,
                color: lastWord
                    ? GameStyle.gold
                    : !_meAlive
                    ? GameStyle.muted
                    : isNight
                    ? GameStyle.moon
                    : action != null
                    ? GameStyle.crimson
                    : GameStyle.gold,
              ),
              // Open voting: everyone sees who votes for whom, live. Under the
              // prompt, so what to do stays near the cameras.
              if (s.phase == GamePhase.voting) ...[
                const SizedBox(height: 12),
                VoteBoard(
                  votes: s.votes,
                  players: s.players,
                  me: widget.me,
                  live: true,
                ),
              ],
              // How the last vote went, until the next one.
              if (s.phase != GamePhase.voting && s.lastVotes.isNotEmpty) ...[
                const SizedBox(height: 12),
                VoteBoard(
                  votes: s.lastVotes,
                  players: s.players,
                  me: widget.me,
                ),
              ],
              const SizedBox(height: 12),
              ChatPanel(
                roomId: widget.roomId,
                state: s,
                private: widget.private,
                me: widget.me,
              ),
              if (events.length > 1) ...[
                const SizedBox(height: 12),
                _EventLog(lines: events.skip(1).toList()),
              ],
            ],
          ),
        ),
        _BottomBar(
          above: action == null || (iSpeak && canSkip)
              ? null
              : _ActionExtras(
                  modes: _donChoice
                      ? _DonModes(
                          mode: action,
                          shot: _done['nightKill'],
                          checked: _done['nightCheck'],
                          nameOf: _name,
                          onChanged: (m) => setState(() {
                            _donMode = m;
                            _selected = _done[m];
                          }),
                        )
                      : null,
                  onSkip:
                      action == 'castVote' && !_sending && _done[action] != ''
                      ? () => _confirm(action, skip: true)
                      : null,
                  skipText: t.gameSkipVote,
                ),
          action: iSpeak && canSkip
              ? _DoneButton(
                  text: t.gameLastWordDone,
                  onPressed: () => widget.onSkipTimer!(true),
                )
              : action == null
              ? (canSkip && !lastWord
                    ? SkipTimerBar(
                        state: s,
                        me: widget.me,
                        onSkip: widget.onSkipTimer!,
                      )
                    : null)
              : _ConfirmButton(
                  text: _selected == null
                      ? t.gameConfirm
                      : _selected == _done[action]
                      ? t.gameConfirmed(_name(_selected!))
                      : '${t.gameConfirm}: ${_name(_selected!)}',
                  onPressed:
                      _selected == null ||
                          _sending ||
                          _selected == _done[action]
                      ? null
                      : () => _confirm(action),
                ),
          roomId: widget.roomId,
        ),
      ],
    );
  }

  String _promptText(AppLocalizations t, String? action) {
    final s = widget.state;
    if (s.phase == GamePhase.lastWord && s.lastWordBy != null) {
      return s.lastWordBy == widget.me
          ? t.gameLastWordYou
          : t.gameLastWordListen(_name(s.lastWordBy!));
    }
    if (!_meAlive) return t.gameDeadSpectator;
    var next = action;
    if (action != null && _done.containsKey(action)) {
      // The Don still has the other pick to make.
      final other = action == 'nightKill' ? 'nightCheck' : 'nightKill';
      if (!_donChoice || _done.containsKey(other)) return t.gameActionSent;
      next = other;
    }
    return switch ((widget.state.phase, next)) {
      (_, 'nightKill') when widget.private?.role == Role.maniac =>
        t.gameNightManiacPrompt,
      (_, 'nightKill') => t.gameNightKillPrompt,
      (_, 'nightGuard') => t.gameNightGuardPrompt,
      (_, 'nightSleep') => t.gameNightSleepPrompt,
      (_, 'nightHeal') => t.gameNightHealPrompt,
      (_, 'nightCheck') when _donChoice => t.gameNightDonCheckPrompt,
      (_, 'nightCheck') => t.gameNightCheckPrompt,
      (_, 'castVote') => t.gameVotePrompt,
      (GamePhase.night, _) => t.gameNightSleep,
      (GamePhase.day, _) when widget.private?.wasAsleep ?? false =>
        t.gameWasAsleep,
      (GamePhase.day, _) => t.gameDayPrompt,
      _ => t.gameActionSent,
    };
  }
}

/// The player saying their last word, with what they typed so far.
class _LastWordStage extends StatelessWidget {
  const _LastWordStage({required this.name, required this.lines});

  final String name;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      key: const ValueKey('last-word-stage'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GameStyle.radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            GameStyle.gold.withValues(alpha: 0.22),
            GameStyle.crimson.withValues(alpha: 0.12),
          ],
        ),
        border: Border.all(
          color: GameStyle.gold.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: GameStyle.glow(GameStyle.gold.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            spacing: 8,
            children: [
              const Icon(
                Icons.record_voice_over_rounded,
                color: GameStyle.gold,
                size: 20,
              ),
              Text(
                t.gameLastWordTag.toUpperCase(),
                style: const TextStyle(
                  color: GameStyle.gold,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          Text(name, style: GameStyle.display(24)),
          for (final l in lines)
            Text(
              '“$l”',
              style: const TextStyle(
                fontSize: 16,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
        ],
      ),
    );
  }
}

/// "Done" for the player ending their own last word.
class _DoneButton extends StatelessWidget {
  const _DoneButton({required this.text, required this.onPressed});

  final String text;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: GameStyle.glow(GameStyle.gold),
      ),
      child: FilledButton.icon(
        key: const ValueKey('last-word-done'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: GameStyle.gold,
          foregroundColor: Palette.background,
        ),
        onPressed: onPressed,
        icon: const Icon(Icons.check_rounded),
        label: Text(text),
      ),
    );
  }
}

/// What to do now, with the latest thing that happened under it.
class _Prompt extends StatelessWidget {
  const _Prompt({
    required this.text,
    required this.icon,
    required this.color,
    this.latest,
  });

  final String text;
  final IconData icon;
  final Color color;
  final String? latest;

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        spacing: 12,
        children: [
          IconBlob(icon: icon, color: color, size: 40),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                Text(
                  text,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    height: 1.3,
                  ),
                ),
                if (latest != null)
                  Text(
                    latest!,
                    style: const TextStyle(
                      color: GameStyle.muted,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventLog extends StatelessWidget {
  const _EventLog({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return GamePanel(
      color: Colors.transparent,
      borderColor: Palette.outlineSoft,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Text(
            t.gameLogTitle.toUpperCase(),
            style: const TextStyle(
              color: GameStyle.muted,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
          for (final line in lines.take(5))
            Text(line, style: const TextStyle(color: GameStyle.muted)),
        ],
      ),
    );
  }
}

/// The bottom of the table: the camera and mic with the main button
/// (Confirm, Skip timer, Done) beside them in one row, so the cameras
/// above get the height. Extra picks (the Don's two modes, skipping the
/// vote) sit over that row.
///
/// Stream 3 (video) owns CallControls. It stays mounted for the whole
/// match: the call joins and leaves with it.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.above,
    required this.action,
    required this.roomId,
  });

  final Widget? above;
  final Widget? action;
  final RoomId roomId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Palette.surfaceSheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            ?above,
            CallControls(roomId: roomId, trailing: action),
          ],
        ),
      ),
    );
  }
}

/// The Don's two night picks: shoot, and look for the Detective. Each
/// shows a tick once it is sent.
class _DonModes extends StatelessWidget {
  const _DonModes({
    required this.mode,
    required this.shot,
    required this.checked,
    required this.nameOf,
    required this.onChanged,
  });

  final String mode;
  final String? shot;
  final String? checked;
  final String Function(UserId) nameOf;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    Widget chip(String value, IconData icon, String label, String? sent) =>
        Expanded(
          child: ChoiceChip(
            key: ValueKey('don-$value'),
            selected: mode == value,
            showCheckmark: false,
            avatar: Icon(sent != null ? Icons.check_circle_rounded : icon),
            label: Text(
              sent != null ? '$label: ${nameOf(sent)}' : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onSelected: (_) => onChanged(value),
          ),
        );
    return Row(
      spacing: 8,
      children: [
        chip('nightKill', Icons.gps_fixed_rounded, t.gameDonShoot, shot),
        chip('nightCheck', Icons.search_rounded, t.gameDonCheck, checked),
      ],
    );
  }
}

/// What goes over the main row while picking: the Don's two modes, and
/// skipping the vote.
class _ActionExtras extends StatelessWidget {
  const _ActionExtras({
    this.modes,
    required this.onSkip,
    required this.skipText,
  });

  final Widget? modes;
  final VoidCallback? onSkip;
  final String skipText;

  @override
  Widget build(BuildContext context) {
    if (modes == null && onSkip == null) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        ?modes,
        if (onSkip != null)
          OutlinedButton(
            key: const ValueKey('skip-vote'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            onPressed: onSkip,
            child: Text(skipText),
          ),
      ],
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({required this.text, required this.onPressed});

  final String text;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: onPressed == null ? null : GameStyle.glow(GameStyle.crimson),
      ),
      child: FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        onPressed: onPressed,
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// How [userId] left the match, from the public log; null while they play.
EliminationCause? outCause(PublicGameState s, UserId userId) {
  for (final e in s.log.reversed) {
    if (e.message == 'eliminated' && e.userId == userId) return e.cause;
  }
  return null;
}
