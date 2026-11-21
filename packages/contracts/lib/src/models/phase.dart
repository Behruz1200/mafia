/// The phases of a match, in the order they normally happen.
///
/// `night -> day -> voting` repeats until a team wins.
enum GamePhase {
  /// Players are gathering; nothing has been dealt.
  lobby,

  /// Roles are dealt; each player sees their own card.
  roleReveal,

  /// Cameras and mics are off for the town; night roles act.
  night,

  /// Everyone alive can talk; the night's result is announced.
  day,

  /// Players vote to eliminate someone.
  voting,

  /// A team has won (or the match was cancelled). Coins are settled.
  ended,
}
