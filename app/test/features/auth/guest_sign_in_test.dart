import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_app/core/providers.dart';
import 'package:mafia_app/features/auth/sign_in_screen.dart';
import 'package:mafia_app/l10n/generated/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

class _GuestAuth extends FakeAuthRepository {
  _GuestAuth() : super(signedIn: false);
  var guests = 0;

  @override
  Future<AuthSession> signInAsGuest() {
    guests++;
    return super.signInAsGuest();
  }
}

void main() {
  Future<_GuestAuth> pump(WidgetTester tester, {required bool guest}) async {
    final auth = _GuestAuth();
    final profiles = FakeProfileRepository(
      UserProfile(
        userId: 'user_0',
        displayName: 'O‘yinchi 1234',
        countryCode: 'UZ',
        createdAt: fixtureNow,
        hasBirthDate: true,
        isAdult: true,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          profileRepositoryProvider.overrideWithValue(profiles),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SignInScreen(showApple: false, showGuest: guest),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return auth;
  }

  testWidgets('no guest button unless switched on', (tester) async {
    await pump(tester, guest: false);
    expect(find.byKey(const Key('guestSignIn')), findsNothing);
  });

  testWidgets('one tap signs in a new guest, who picks only a name', (
    tester,
  ) async {
    final auth = await pump(tester, guest: true);
    await tester.ensureVisible(find.byKey(const Key('guestSignIn')));
    await tester.tap(find.text('Play as guest'));
    await tester.pumpAndSettle();
    expect(auth.guests, 1);
    expect(find.byKey(const Key('nameField')), findsOneWidget);
    expect(find.byKey(const Key('birthDateButton')), findsNothing);
    final go = tester.widget<FilledButton>(
      find.byKey(const Key('finishSetup')),
    );
    expect(go.onPressed, isNotNull);
  });
}
