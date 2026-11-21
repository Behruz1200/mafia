import 'dart:convert';

import 'package:contracts/contracts.dart';
import 'package:contracts/testing.dart';
import 'package:test/test.dart';

Json wire(Json j) => jsonDecode(jsonEncode(j)) as Json;

void main() {
  test('UserProfile keeps hasBirthDate and defaults it to false', () {
    final p = UserProfile(
      userId: 'u',
      displayName: 'Aziza',
      hasBirthDate: true,
      createdAt: fixtureNow,
    );
    expect(UserProfile.fromJson(wire(p.toJson())).hasBirthDate, isTrue);

    final old = p.toJson()..remove('hasBirthDate');
    expect(UserProfile.fromJson(old).hasBirthDate, isFalse);
  });

  test('UpdateProfileRequest sends only the fields that change', () {
    final r = UpdateProfileRequest(
      displayName: 'Bekzod',
      birthDate: DateTime(2001, 3, 9),
    );
    expect(r.toJson(), {'displayName': 'Bekzod', 'birthDate': '2001-03-09'});
    final back = UpdateProfileRequest.fromJson(wire(r.toJson()));
    expect(back.displayName, 'Bekzod');
    expect(back.locale, isNull);
    expect(back.birthDate, DateTime(2001, 3, 9));
  });

  test('AppleSignInRequest and RefreshRequest round-trip', () {
    const a = AppleSignInRequest(
      identityToken: 'jwt',
      rawNonce: 'n',
      displayName: 'Kamola',
    );
    final back = AppleSignInRequest.fromJson(wire(a.toJson()));
    expect(back.identityToken, 'jwt');
    expect(back.rawNonce, 'n');
    expect(back.authorizationCode, isNull);
    expect(back.displayName, 'Kamola');

    const r = RefreshRequest(refreshToken: 't');
    expect(RefreshRequest.fromJson(wire(r.toJson())).refreshToken, 't');
  });

  test('fake profile works out the age gate', () async {
    final repo = FakeProfileRepository(
      UserProfile(userId: 'u', displayName: 'A', createdAt: fixtureNow),
    );
    final now = DateTime.now();
    final minor = await repo.setBirthDate(DateTime(now.year - 17, 1, 1));
    expect(minor.hasBirthDate, isTrue);
    expect(minor.isAdult, isFalse);
    final adult = await repo.setBirthDate(DateTime(now.year - 30, 1, 1));
    expect(adult.isAdult, isTrue);
  });
}
