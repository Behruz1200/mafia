import '../models/account.dart';
import '../models/call.dart';
import '../models/game_action.dart';
import '../models/game_state.dart';
import '../models/ids.dart';
import '../models/match_result.dart';
import '../models/room.dart';
import '../models/wallet.dart';

// App-side interfaces. Each feature in the app depends only on these, never
// on another feature's code. Real versions talk to the game server; fakes
// in `package:contracts/testing.dart` let every stream work offline.

/// Owned by stream 5 (accounts).
abstract interface class AuthRepository {
  /// Emits the current session, or null when signed out.
  Stream<AuthSession?> watchSession();
  AuthSession? get currentSession;

  Future<void> startPhoneSignIn(String phoneE164);
  Future<AuthSession> verifyPhoneCode(String phoneE164, String code);
  Future<AuthSession> signInWithApple();
  Future<void> signOut();

  /// Apple requires in-app account deletion.
  Future<void> deleteAccount();
}

/// Owned by stream 5. Profiles live only on the server in Uzbekistan.
abstract interface class ProfileRepository {
  Stream<UserProfile?> watchMyProfile();

  /// Sends the name, avatar and language from [profile]. Country, age and
  /// ids are decided by the server and ignored here.
  Future<UserProfile> updateMyProfile(UserProfile profile);

  /// Age gate: the player's birth date, given once. The server works out
  /// `isAdult` from it and keeps the date to itself.
  Future<UserProfile> setBirthDate(DateTime birthDate);
}

/// Owned by stream 2 (rooms and server).
abstract interface class RoomRepository {
  Future<Room> createRoom(RoomSettings settings);
  Future<Room> joinByCode(InviteCode code);
  Future<Room> quickMatch();
  Future<void> leave(RoomId roomId);

  Stream<Room> watchRoom(RoomId roomId);
  Stream<PublicGameState> watchPublicState(RoomId roomId);
  Stream<PrivatePlayerState> watchMyState(RoomId roomId);
  Stream<MatchResult> watchMatchEnd(RoomId roomId);

  /// Send a player action. The server answers with new state, or an error
  /// on the socket.
  Future<void> send(RoomId roomId, GameAction action);
}

/// Owned by stream 4 (coins).
abstract interface class WalletRepository {
  Stream<WalletBalance> watchBalance();
  Future<List<LedgerEntry>> history({int limit = 50});
  Future<List<CoinPack>> coinPacks();

  /// Runs the store purchase and returns the new balance once the server
  /// has verified it.
  Future<WalletBalance> buy(CoinPack pack);
}

/// Owned by stream 3 (video). The game screen embeds the call widget and
/// drives it through this.
abstract interface class CallController {
  Stream<List<CallParticipant>> watchParticipants();
  Future<void> join(CallGrant grant);
  Future<void> setCamera({required bool on});
  Future<void> setMic({required bool on});
  Future<void> leave();
}
