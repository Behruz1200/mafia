import 'package:contracts/contracts.dart';

import '../rooms/ports.dart';
import 'auth_module.dart';

/// Rooms' [PlayerDirectory] backed by real profiles: names, country and
/// the 18+ flag for staked rooms.
class AuthPlayers implements PlayerDirectory {
  const AuthPlayers(this.auth);
  final AuthModule auth;

  @override
  Future<UserProfile?> profile(UserId userId) async {
    try {
      return await auth.profileOf(userId);
    } on Object {
      return null; // accounts not configured: rooms fall back to anonymous
    }
  }
}
