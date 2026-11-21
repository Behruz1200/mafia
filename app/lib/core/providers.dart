import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/data/api.dart';
import '../features/auth/data/http_auth_repository.dart';
import '../features/profile/data/http_profile_repository.dart';
import 'config.dart';

// One provider per contract. Features read these, never each other's
// classes. When a stream ships its real implementation it replaces the
// `_notYet` branch of its own provider, nothing else.

Never _notYet(String stream) => throw UnimplementedError(
  '$stream has not shipped a real implementation yet; run with USE_FAKES=true',
);

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
final roomRepositoryProvider = Provider<RoomRepository>(
  (ref) => AppConfig.useFakes ? FakeRoomRepository() : _notYet('Rooms'),
);

/// Stream 4 (coins).
final walletRepositoryProvider = Provider<WalletRepository>(
  (ref) => AppConfig.useFakes ? FakeWalletRepository() : _notYet('Coins'),
);

/// Stream 3 (video).
final callControllerProvider = Provider<CallController>(
  (ref) => AppConfig.useFakes ? FakeCallController() : _notYet('Video'),
);

final sessionProvider = StreamProvider<AuthSession?>(
  (ref) => ref.watch(authRepositoryProvider).watchSession(),
);

final balanceProvider = StreamProvider<WalletBalance>(
  (ref) => ref.watch(walletRepositoryProvider).watchBalance(),
);
