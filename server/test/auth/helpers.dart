import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:server/auth/src/apple.dart';
import 'package:server/auth/src/auth_config.dart';
import 'package:server/auth/src/auth_service.dart';
import 'package:server/auth/src/memory_store.dart';
import 'package:server/auth/src/sms.dart';
import 'package:server/auth/src/store.dart';

const testSecret = 'test-secret-that-is-at-least-32-characters-long';

/// Records every SMS instead of sending it.
class RecordingSms implements SmsSender {
  final sent = <(String, String)>[];
  bool fail = false;

  /// The code in the last message.
  String get lastCode => RegExp(r'\d{6}').firstMatch(sent.last.$2)![0]!;

  @override
  Future<void> send(String phoneE164, String text) async {
    if (fail) throw const HttpException('down');
    sent.add((phoneE164, text));
  }
}

/// A clock tests can move.
class TestClock {
  DateTime now = DateTime.utc(2026, 11, 21, 12);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

class Harness {
  Harness({
    AppleIdVerifier? apple,
    Map<String, String> testPhones = const {},
    bool guestSignIn = false,
    int guestsPerHour = 30,
  }) : clock = TestClock() {
    store = MemoryAccountStore(now: clock.call);
    service = AuthService(
      config: AuthConfig(
        jwtSecret: testSecret,
        regions: const RegionPolicy(
          launchCountries: {'UZ'},
          stakeCountries: {'UZ'},
        ),
        testPhones: testPhones,
        guestSignIn: guestSignIn,
        guestsPerHour: guestsPerHour,
      ),
      store: store,
      sms: sms,
      apple: apple ?? AppleIdVerifier(audiences: const {}),
      now: clock.call,
    );
  }

  final TestClock clock;
  final sms = RecordingSms();
  late final MemoryAccountStore store;
  late final AuthService service;

  /// Signs in a new phone user and returns the session.
  Future<AuthSession> signIn([String phone = '+998901234567']) async {
    await service.startPhone(phone);
    return service.verifyPhone(phone, sms.lastCode);
  }

  AccountStore get accounts => store;
}
