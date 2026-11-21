import 'package:contracts/contracts.dart';

/// What the rooms code needs from other streams, kept as small seams so
/// each stream can plug in its real version in `lib/src/app.dart` without
/// touching this folder.

/// Turns an access token into the signed-in user. Stream 5 (accounts)
/// issues the tokens; [JwtTokenVerifier] checks them with `JWT_SECRET`.
abstract interface class TokenVerifier {
  /// The user id, or null if the token is missing, expired or forged.
  UserId? verify(String token);
}

/// Rejects every token. The default until auth is configured, so a server
/// started without `JWT_SECRET` never lets anyone into a room.
class DenyAllTokens implements TokenVerifier {
  const DenyAllTokens();
  @override
  UserId? verify(String token) => null;
}

/// Local development only (`DEV_AUTH=true`): the token `dev:<userId>` signs
/// in as that user. Never enabled unless the variable is set.
class DevTokenVerifier implements TokenVerifier {
  const DevTokenVerifier();
  @override
  UserId? verify(String token) {
    if (!token.startsWith('dev:')) return null;
    final id = token.substring(4);
    return RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id) ? id : null;
  }
}

/// Looks up the profile behind a user id: the name shown at the table, and
/// the country and age gate used for staked rooms. Stream 5 supplies the
/// real version backed by PostgreSQL.
abstract interface class PlayerDirectory {
  Future<UserProfile?> profile(UserId userId);
}

/// Until profiles exist: a short generated name, and no country or age
/// gate, so staked rooms stay closed.
class AnonymousPlayers implements PlayerDirectory {
  const AnonymousPlayers();
  @override
  Future<UserProfile?> profile(UserId userId) async => null;
}

/// Until stream 4 wires the real wallet: free matches work, staked ones are
/// refused before any coin moves.
class FreeMatchesOnlyWallet implements WalletSettlement {
  const FreeMatchesOnlyWallet();

  @override
  Future<WalletBalance> balance(UserId userId) async =>
      WalletBalance(userId: userId, available: 0);

  @override
  Future<void> holdStakes({
    required MatchId matchId,
    required List<UserId> players,
    required int stake,
  }) async {
    if (stake > 0) throw InsufficientCoins(players);
  }

  @override
  Future<void> settle(MatchResult result) async {}
}
