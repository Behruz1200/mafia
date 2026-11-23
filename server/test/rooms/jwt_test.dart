import 'package:server/realtime/socket_handler.dart';
import 'package:server/rooms/jwt.dart';
import 'package:server/rooms/ports.dart';
import 'package:contracts/contracts.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 21, 12);
  final exp = now.millisecondsSinceEpoch ~/ 1000 + 900;
  final v = JwtTokenVerifier('a-secret-of-sixteen+', now: () => now);

  test('accepts a valid access token', () {
    expect(v.verify(v.sign({'sub': 'user-1', 'exp': exp})), 'user-1');
    expect(
      v.verify(v.sign({'sub': 'user-1', 'exp': exp, 'typ': 'access'})),
      'user-1',
    );
  });

  test('refuses expired, forged, refresh and malformed tokens', () {
    expect(v.verify(v.sign({'sub': 'u', 'exp': exp - 1000})), isNull);
    final other = JwtTokenVerifier('another-secret-16chars', now: () => now);
    expect(v.verify(other.sign({'sub': 'u', 'exp': exp})), isNull);
    expect(
      v.verify(v.sign({'sub': 'u', 'exp': exp, 'typ': 'refresh'})),
      isNull,
    );
    expect(v.verify(v.sign({'sub': 'u'})), isNull);
    expect(v.verify('not.a.jwt'), isNull);
    expect(v.verify(''), isNull);
    // alg "none" with the signature stripped.
    final parts = v.sign({'sub': 'u', 'exp': exp}).split('.');
    expect(v.verify('eyJhbGciOiJub25lIn0.${parts[1]}.'), isNull);
  });

  test('dev tokens only when enabled, and only plain ids', () {
    const d = DevTokenVerifier();
    expect(d.verify('dev:alice'), 'alice');
    expect(d.verify('dev:'), isNull);
    expect(d.verify('dev:a b'), isNull);
    expect(const DenyAllTokens().verify('dev:alice'), isNull);
  });

  test('the socket re-stamps actions with the signed-in user', () {
    final a = stampActor(
      const NightKill(actorId: 'someone-else', targetId: 't'),
      'me',
    );
    expect(a, isA<NightKill>().having((k) => k.actorId, 'actor', 'me'));
    expect(
      stampActor(const SkipPhase(actorId: 'x', skip: false), 'me'),
      isA<SkipPhase>()
          .having((k) => k.actorId, 'actor', 'me')
          .having((k) => k.skip, 'skip', false),
    );
    expect(stampActor(const PhaseTimeout(), 'me'), isNull);
    expect(stampActor(const PlayerLeft(userId: 'x'), 'me'), isNull);
    // Last words come in as chat, never as an action from the app.
    expect(
      stampActor(const SayLastWord(actorId: 'x', text: 'hi'), 'me'),
      isNull,
    );
  });
}
