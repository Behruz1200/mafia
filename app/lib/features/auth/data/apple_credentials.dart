import 'dart:convert';
import 'dart:math';

import 'package:contracts/contracts.dart';
import 'package:crypto/crypto.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Opens Apple's sign-in sheet. Returns null when the player cancels.
typedef AppleCredentialSource = Future<AppleSignInRequest?> Function();

/// The real Sign in with Apple sheet (iOS). Apple signs the SHA-256 of a
/// fresh nonce into the token; the server checks it against the raw one.
Future<AppleSignInRequest?> appleSignInSheet() async {
  final rand = Random.secure();
  final rawNonce = base64Url.encode(
    List<int>.generate(32, (_) => rand.nextInt(256)),
  );
  try {
    final c = await SignInWithApple.getAppleIDCredential(
      scopes: const [AppleIDAuthorizationScopes.fullName],
      nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
    );
    final token = c.identityToken;
    if (token == null) return null;
    final name = [
      c.givenName,
      c.familyName,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    return AppleSignInRequest(
      identityToken: token,
      rawNonce: rawNonce,
      authorizationCode: c.authorizationCode,
      displayName: name.isEmpty ? null : name,
    );
  } on SignInWithAppleAuthorizationException catch (e) {
    if (e.code == AuthorizationErrorCode.canceled) return null;
    rethrow;
  }
}
