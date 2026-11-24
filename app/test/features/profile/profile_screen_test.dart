import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mafia_app/core/providers.dart';
import 'package:mafia_app/features/profile/profile_screen.dart';
import 'package:mafia_app/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late FakeAuthRepository auth;
  late FakeProfileRepository profiles;

  Future<void> pump(WidgetTester tester, UserProfile profile) async {
    auth = FakeAuthRepository();
    profiles = FakeProfileRepository(profile);
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
        GoRoute(
          path: '/sign-in',
          builder: (_, _) => const Scaffold(body: Text('signed out')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          profileRepositoryProvider.overrideWithValue(profiles),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: const [Locale('en')],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  UserProfile profile({bool hasBirthDate = true, bool isAdult = true}) =>
      UserProfile(
        userId: 'user_0',
        displayName: 'Aziza',
        hasBirthDate: hasBirthDate,
        isAdult: isAdult,
        createdAt: fixtureNow,
      );

  testWidgets('renames the player', (tester) async {
    await pump(tester, profile());
    await tester.enterText(find.byKey(const Key('profileName')), 'Umida');
    await tester.tap(find.byKey(const Key('saveProfile')));
    await tester.pumpAndSettle();
    expect((await profiles.watchMyProfile().first)!.displayName, 'Umida');
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('shows the age gate state', (tester) async {
    await pump(tester, profile());
    expect(find.text('Age confirmed: 18+'), findsOneWidget);
  });

  testWidgets('asks for a birth date when there is none', (tester) async {
    await pump(tester, profile(hasBirthDate: false, isAdult: false));
    await tester.tap(find.byKey(const Key('addBirthDate')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect((await profiles.watchMyProfile().first)!.hasBirthDate, isTrue);
  });

  testWidgets('deleting the account asks first, then signs out', (
    tester,
  ) async {
    await pump(tester, profile());
    await tester.scrollUntilVisible(
      find.byKey(const Key('deleteAccount')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deleteAccount')));
    await tester.pumpAndSettle();
    expect(find.text('Delete your account?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(auth.currentSession, isNotNull);

    await tester.tap(find.byKey(const Key('deleteAccount')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmDelete')));
    await tester.pumpAndSettle();
    expect(auth.currentSession, isNull);
    expect(find.text('signed out'), findsOneWidget);
  });

  testWidgets('sign out goes back to sign-in', (tester) async {
    await pump(tester, profile());
    await tester.ensureVisible(find.byKey(const Key('signOut')));
    await tester.tap(find.byKey(const Key('signOut')));
    await tester.pumpAndSettle();
    expect(auth.currentSession, isNull);
    expect(find.text('signed out'), findsOneWidget);
  });
}
