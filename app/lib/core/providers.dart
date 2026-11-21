import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/rooms/data/http_room_repository.dart';
import '../features/shop/data/wallet_providers.dart';
import 'config.dart';

// One provider per contract. Features read these, never each other's
// classes. When a stream ships its real implementation it replaces the
// `_notYet` branch of its own provider, nothing else.

Never _notYet(String stream) => throw UnimplementedError(
  '$stream has not shipped a real implementation yet; run with USE_FAKES=true',
);

/// Stream 5 (accounts).
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AppConfig.useFakes ? FakeAuthRepository() : _notYet('Accounts'),
);

/// Stream 5 (accounts).
final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => AppConfig.useFakes ? FakeProfileRepository() : _notYet('Accounts'),
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
final callControllerProvider = Provider<CallController>(
  (ref) => AppConfig.useFakes ? FakeCallController() : _notYet('Video'),
);

final sessionProvider = StreamProvider<AuthSession?>(
  (ref) => ref.watch(authRepositoryProvider).watchSession(),
);

final balanceProvider = StreamProvider<WalletBalance>(
  (ref) => ref.watch(walletRepositoryProvider).watchBalance(),
);
