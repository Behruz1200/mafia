import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/data/api.dart';
import '../features/auth/data/http_auth_repository.dart';
import '../features/call/data/livekit_call_controller.dart';
import '../features/profile/data/http_profile_repository.dart';
import '../features/rooms/data/http_room_repository.dart';
import '../features/shop/data/wallet_providers.dart';
import 'config.dart';

// One provider per contract. Features read these, never each other's
// classes. With USE_FAKES=true every provider returns its fake; otherwise
// each returns its stream's real implementation.

/// Stream 5 (accounts).
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (AppConfig.useFakes) return FakeAuthRepository();
  final repo = HttpAuthRepository(
    api: AccountsApi(baseUrl: AppConfig.apiBaseUrl),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

/// Stream 5 (accounts).
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  if (AppConfig.useFakes) return FakeProfileRepository();
  final repo = HttpProfileRepository(
    api: AccountsApi(baseUrl: AppConfig.apiBaseUrl),
    auth: ref.watch(authRepositoryProvider) as HttpAuthRepository,
  );
  ref.onDispose(repo.dispose);
  return repo;
});

/// Stream 5 (accounts). The signed-in player's profile.
final myProfileProvider = StreamProvider<UserProfile?>(
  (ref) => ref.watch(profileRepositoryProvider).watchMyProfile(),
);

/// Stream 2 (rooms and server).
final roomRepositoryProvider = Provider<RoomRepository>((ref) {
  if (AppConfig.useFakes) return FakeRoomRepository();
  final auth = ref.watch(authRepositoryProvider);
  final repo = HttpRoomRepository(
    baseUrl: Uri.parse(AppConfig.apiBaseUrl),
    accessToken: () => auth.currentSession?.accessToken,
  );
  ref.onDispose(repo.close);
  return repo;
});

/// Stream 4 (coins).
final walletRepositoryProvider = Provider<WalletRepository>(
  (ref) =>
      AppConfig.useFakes ? FakeWalletRepository() : createWalletRepository(ref),
);

/// Stream 3 (video).
final callControllerProvider = Provider<CallController>((ref) {
  if (AppConfig.useFakes) return FakeCallController();
  final call = LiveKitCallController();
  ref.onDispose(call.dispose);
  return call;
});

final sessionProvider = StreamProvider<AuthSession?>(
  (ref) => ref.watch(authRepositoryProvider).watchSession(),
);

final balanceProvider = StreamProvider<WalletBalance>(
  (ref) => ref.watch(walletRepositoryProvider).watchBalance(),
);
