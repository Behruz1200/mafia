/// The `PublicEvent.message` keys the engine writes to the match log. The
/// app localises each one; it never shows them raw.
abstract final class EventKeys {
  /// Roles were dealt.
  static const rolesDealt = 'rolesDealt';

  /// Night began. Town cameras and mics go off.
  static const nightStarted = 'nightStarted';

  /// The day began and the night's result is in the events before it.
  static const dayStarted = 'dayStarted';

  /// Voting opened.
  static const votingStarted = 'votingStarted';

  /// [PublicEvent.userId] is out; [PublicEvent.cause] says why.
  static const eliminated = 'eliminated';

  /// The night passed with no one killed (no pick, the Doctor saved them,
  /// or they were the Immortal; the town is not told which).
  static const nobodyDied = 'nobodyDied';

  /// Two or more players tied for most votes, so no one is out.
  static const voteTied = 'voteTied';

  /// Skips won or no one was voted for, so no one is out.
  static const nobodyVotedOut = 'nobodyVotedOut';

  /// Every living player agreed to end the timer early (day or role
  /// reveal), so the next phase started straight away.
  static const phaseSkipped = 'phaseSkipped';

  /// [PublicEvent.userId] typed a line of their last word;
  /// [PublicEvent.text] holds it.
  static const lastWord = 'lastWord';

  /// [PublicEvent.userId] left mid-match and forfeits their stake.
  static const playerLeft = 'playerLeft';

  /// The town found every Mafia member.
  static const townWon = 'townWon';

  /// The Mafia reached as many players as everyone else.
  static const mafiaWon = 'mafiaWon';

  /// The Maniac is one of the last two players alive.
  static const maniacWon = 'maniacWon';
}

/// The `Rejected.code` values the engine returns.
abstract final class RejectCodes {
  static const wrongPhase = 'wrong_phase';
  static const matchEnded = 'match_ended';
  static const notHost = 'not_host';
  static const notYourRole = 'not_your_role';
  static const unknownPlayer = 'unknown_player';
  static const actorDead = 'actor_dead';
  static const targetDead = 'target_dead';
  static const targetSelf = 'target_self';
  static const targetTeammate = 'target_teammate';
  static const alreadyChecked = 'already_checked';
  static const sameHealTwice = 'same_heal_twice';
  static const sameGuardTwice = 'same_guard_twice';
  static const sameSleepTwice = 'same_sleep_twice';
  static const selfHealUsed = 'self_heal_used';
  static const alreadyLeft = 'already_left';
  static const tooEarly = 'too_early';
  static const emptyText = 'empty_text';
  static const lastWordFull = 'last_word_full';
}
