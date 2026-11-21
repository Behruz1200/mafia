import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import 'wallet_config.dart';

/// What Apple says about one in-app purchase transaction (the decoded
/// `JWSTransactionDecodedPayload`, only the fields we use).
class AppStoreTransaction {
  const AppStoreTransaction({
    required this.transactionId,
    required this.originalTransactionId,
    required this.productId,
    required this.bundleId,
    required this.environment,
    required this.type,
    this.purchaseDate,
    this.revocationDate,
  });

  final String transactionId;
  final String originalTransactionId;
  final String productId;
  final String bundleId;

  /// `Production` or `Sandbox`.
  final String environment;

  /// `Consumable` for coin packs.
  final String type;
  final DateTime? purchaseDate;

  /// Set when Apple refunded or revoked the purchase.
  final DateTime? revocationDate;

  bool get isSandbox => environment == 'Sandbox';
  bool get isRevoked => revocationDate != null;

  factory AppStoreTransaction.fromPayload(Map<String, Object?> j) {
    DateTime? ms(Object? v) => v == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((v as num).toInt(), isUtc: true);
    return AppStoreTransaction(
      transactionId: j['transactionId']! as String,
      originalTransactionId:
          j['originalTransactionId'] as String? ??
          j['transactionId']! as String,
      productId: j['productId']! as String,
      bundleId: j['bundleId']! as String,
      environment: j['environment'] as String? ?? 'Production',
      type: j['type'] as String? ?? '',
      purchaseDate: ms(j['purchaseDate']),
      revocationDate: ms(j['revocationDate']),
    );
  }
}

/// Looks a transaction up with Apple. Implemented by [AppStoreServerApi];
/// tests use a fake.
abstract interface class AppStoreVerifier {
  /// Null when Apple does not know the transaction.
  Future<AppStoreTransaction?> transaction(String transactionId);
}

/// Reads the payload of a JWS without checking its signature.
///
/// We only do this for (a) responses fetched from Apple over TLS, and
/// (b) store notifications, where the payload is only used as a hint and
/// every fact is fetched again from Apple before we act on it.
Map<String, Object?> unverifiedJwsPayload(String jws) {
  final parts = jws.split('.');
  if (parts.length != 3) throw const FormatException('Not a JWS');
  final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
  return jsonDecode(payload) as Map<String, Object?>;
}

/// The App Store Server API "Get Transaction Info" call, signed with our
/// In-App Purchase key. The transaction id the app sends is never trusted
/// on its own: coins are credited only after Apple confirms it here.
class AppStoreServerApi implements AppStoreVerifier {
  AppStoreServerApi(this.config, {http.Client? client})
    : _http = client ?? http.Client();

  final AppleConfig config;
  final http.Client _http;

  static const _production = 'https://api.storekit.itunes.apple.com';
  static const _sandbox = 'https://api.storekit-sandbox.itunes.apple.com';

  String _token() {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final jwt = JWT(
      {
        'iss': config.issuerId,
        'iat': now,
        'exp': now + 15 * 60,
        'aud': 'appstoreconnect-v1',
        'bid': config.bundleId,
      },
      header: {'kid': config.keyId, 'typ': 'JWT'},
    );
    return jwt.sign(
      ECPrivateKey(config.privateKeyPem),
      algorithm: JWTAlgorithm.ES256,
    );
  }

  Future<AppStoreTransaction?> _lookup(String base, String id) async {
    final res = await _http.get(
      Uri.parse('$base/inApps/v1/transactions/${Uri.encodeComponent(id)}'),
      headers: {'authorization': 'Bearer ${_token()}'},
    );
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw AppStoreUnavailable(res.statusCode, res.body);
    }
    final body = jsonDecode(res.body) as Map<String, Object?>;
    final signed = body['signedTransactionInfo'] as String?;
    if (signed == null) return null;
    return AppStoreTransaction.fromPayload(unverifiedJwsPayload(signed));
  }

  @override
  Future<AppStoreTransaction?> transaction(String transactionId) async {
    // Apple's advice: try production first, then sandbox (App Review and
    // TestFlight buy in the sandbox against the production server).
    final found = await _lookup(_production, transactionId);
    if (found != null || config.sandbox == SandboxPolicy.deny) return found;
    return _lookup(_sandbox, transactionId);
  }
}

class AppStoreUnavailable implements Exception {
  const AppStoreUnavailable(this.status, this.body);
  final int status;
  final String body;
  @override
  String toString() => 'AppStoreUnavailable($status)';
}
