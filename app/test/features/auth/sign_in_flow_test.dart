import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_app/app.dart';
import 'package:mafia_app/core/providers.dart';
import 'package:mafia_app/features/auth/data/api.dart';
import 'package:material_ui/material_ui.dart';

/// Signed out; a code of 000000 is wrong, anything else works.
class _ScriptedAuth extends FakeAuthRepository {
  _ScriptedAuth() : super(signedIn: false);
  final phones = <String>[];

  @override
  Future<void> startPhoneSignIn(String phoneE164) async =>
      phones.add(phoneE164);

  @override
  Future<AuthSession> verifyPhoneCode(String phoneE164, String code) {
    if (code == '000000') throw const ApiException('code_invalid');
    return super.verifyPhoneCode(phoneE164, code);
  }
}

void main() {
  late _ScriptedAuth auth;
  late FakeProfileRepository profiles;

  Future<void> pumpApp(WidgetTester tester, {required bool newPlayer}) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    auth = _ScriptedAuth();
    profiles = FakeProfileRepository(
      UserProfile(
        userId: 'user_0',
        displayName: 'O‘yinchi 1234',
        countryCode: 'UZ',
        hasBirthDate: !newPlayer,
        isAdult: !newPlayer,
        createdAt: fixtureNow,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          profileRepositoryProvider.overrideWithValue(profiles),
        ],
        child: const MafiaApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterPhoneAndCode(WidgetTester tester, String code) async {
    await tester.enterText(find.byKey(const Key('phoneField')), '901234567');
    await tester.pump();
    await tester.tap(find.byKey(const Key('sendCode')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('codeField')), code);
    await tester.pumpAndSettle();
  }

  testWidgets('a new player signs in by phone and fills in "about you"', (
    tester,
  ) async {
    await pumpApp(tester, newPlayer: true);
    expect(find.text('Sign in'), findsWidgets);

    await enterPhoneAndCode(tester, '123456');
    expect(auth.phones, ['+998901234567']);
    expect(find.text('About you'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('nameField')), 'Shahzoda');
    await tester.tap(find.byKey(const Key('birthDateButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finishSetup')));
    await tester.pumpAndSettle();

    final p = await profiles.watchMyProfile().first;
    expect(p!.displayName, 'Shahzoda');
    expect(p.hasBirthDate, isTrue);
    expect(find.text('Quick match'), findsOneWidget); // the lobby
    // The setup screen's own Continue/OK must not linger with a timer.
    await tester.pump(const Duration(minutes: 2));
  });

  testWidgets('a returning player goes straight to the lobby', (tester) async {
    await pumpApp(tester, newPlayer: false);
    await enterPhoneAndCode(tester, '123456');
    expect(find.text('Quick match'), findsOneWidget);
    await tester.pump(const Duration(minutes: 2));
  });

  testWidgets('a wrong code shows a translated error', (tester) async {
    await pumpApp(tester, newPlayer: false);
    await enterPhoneAndCode(tester, '000000');
    expect(find.text('Wrong code'), findsOneWidget);
    await tester.pump(const Duration(minutes: 2));
    expect(find.text('Send the code again'), findsOneWidget);
  });
}
