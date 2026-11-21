import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/sign_in_screen.dart';
import '../features/game/game_screen.dart';
import '../features/lobby/lobby_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/shop/shop_screen.dart';
import 'providers.dart';
import 'routes.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  return GoRouter(
    initialLocation: Routes.lobby,
    redirect: (context, state) {
      final signedIn = auth.currentSession != null;
      final atSignIn = state.matchedLocation == Routes.signIn;
      if (!signedIn && !atSignIn) return Routes.signIn;
      if (signedIn && atSignIn) return Routes.lobby;
      return null;
    },
    routes: [
      GoRoute(path: Routes.signIn, builder: (_, _) => const SignInScreen()),
      GoRoute(path: Routes.lobby, builder: (_, _) => const LobbyScreen()),
      GoRoute(path: Routes.shop, builder: (_, _) => const ShopScreen()),
      GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen()),
      GoRoute(
        path: '/room/:roomId',
        builder: (_, state) =>
            GameScreen(roomId: state.pathParameters['roomId']!),
      ),
    ],
  );
});
