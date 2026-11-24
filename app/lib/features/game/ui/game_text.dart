import 'package:contracts/contracts.dart';

import '../../../l10n/generated/app_localizations.dart';

/// Turns contract values (roles, teams, log keys) into the player's
/// language. The server only ever sends stable keys, never text.
extension GameText on AppLocalizations {
  String roleName(Role role) => switch (role) {
    Role.civilian => gameRoleCivilian,
    Role.doctor => gameRoleDoctor,
    Role.detective => gameRoleDetective,
    Role.mafia => gameRoleMafia,
    Role.don => gameRoleDon,
  };

  String roleGoal(Role role) => switch (role) {
    Role.civilian => gameRoleCivilianGoal,
    Role.doctor => gameRoleDoctorGoal,
    Role.detective => gameRoleDetectiveGoal,
    Role.mafia => gameRoleMafiaGoal,
    Role.don => gameRoleDonGoal,
  };

  String teamName(Team team) => switch (team) {
    Team.town => gameTeamTown,
    Team.mafia => gameTeamMafia,
  };

  String phaseName(GamePhase phase) => switch (phase) {
    GamePhase.lobby => gameWaitingTitle,
    GamePhase.roleReveal => gamePhaseRoleReveal,
    GamePhase.night => phaseNight,
    GamePhase.day => phaseDay,
    GamePhase.voting => phaseVoting,
    GamePhase.ended => gamePhaseEnded,
    GamePhase.lastWord => phaseLastWord,
  };

  /// One log line, or null for keys this version of the app does not know
  /// (so a newer server never shows players a raw key).
  String? eventText(PublicEvent e, String Function(UserId) nameOf) {
    final name = e.userId == null ? '' : nameOf(e.userId!);
    return switch (e.message) {
      'eliminated' => switch (e.cause) {
        EliminationCause.killedAtNight => gameEventKilled(name),
        EliminationCause.votedOut => gameEventVotedOut(name),
        EliminationCause.leftMatch => gameEventLeft(name),
        null => null,
      },
      'playerLeft' => gameEventLeft(name),
      'nobodyDied' => gameEventNobodyDied,
      'voteTied' => gameEventVoteTied,
      'nobodyVotedOut' => gameEventNobodyVotedOut,
      'phaseSkipped' => gameEventPhaseSkipped,
      'lastWord' when e.text != null => gameEventLastWord(name, e.text!),
      _ => null,
    };
  }

  /// What to tell the player when the server refused something, by its
  /// stable error code, else [fallback]. Null for refusals that only
  /// happen when the phase moved on just as they tapped; those need no
  /// message.
  String? errorText(String code, {String? fallback}) => switch (code) {
    'room_not_found' => errorRoomNotFound,
    'room_full' => errorRoomFull,
    'room_in_match' => errorRoomInMatch,
    'already_in_match' => errorAlreadyInMatch,
    'not_enough_players' => errorNotEnoughPlayers,
    'not_host' => errorNotHost,
    'stakes_not_allowed' => errorStakesNotAllowed,
    'insufficient_coins' => lobbyNotEnoughCoins,
    'not_in_room' => errorNotInRoom,
    'server_busy' => errorServerBusy,
    'chat_too_fast' => errorChatTooFast,
    'chat_closed' => errorChatClosed,
    'same_heal_twice' => errorSameHealTwice,
    'self_heal_used' => errorSelfHealUsed,
    'already_checked' => errorAlreadyChecked,
    'target_teammate' => errorTargetTeammate,
    'wrong_phase' || 'match_ended' || 'too_early' || 'chat_empty' => null,
    'target_dead' || 'actor_dead' || 'already_left' => null,
    _ => fallback,
  };
}
