import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'phone.dart';

/// Sends the sign-in code by SMS.
abstract interface class SmsSender {
  Future<void> send(String phoneE164, String text);
}

/// Development only: prints the message to the server log instead of
/// sending it. Used when `SMS_PROVIDER` is `console` (the default).
class ConsoleSmsSender implements SmsSender {
  ConsoleSmsSender([this._out]);
  final IOSink? _out;

  @override
  Future<void> send(String phoneE164, String text) async =>
      (_out ?? stdout).writeln('[sms] to $phoneE164: $text');
}

/// Eskiz (notify.eskiz.uz), a local Uzbek SMS provider. Needs an Eskiz
/// account, and the message text must match a template approved in the
/// Eskiz cabinet.
class EskizSmsSender implements SmsSender {
  EskizSmsSender({
    required this.email,
    required this.password,
    this.from = '4546',
    http.Client? client,
    Uri? baseUrl,
  }) : _client = client ?? http.Client(),
       _base = baseUrl ?? Uri.parse('https://notify.eskiz.uz/api/');

  final String email;
  final String password;

  /// Sender name approved by Eskiz; `4546` is their default short code.
  final String from;
  final http.Client _client;
  final Uri _base;
  String? _token;

  Future<String> _login() async {
    final res = await _client.post(
      _base.resolve('auth/login'),
      body: {'email': email, 'password': password},
    );
    if (res.statusCode != 200) {
      throw HttpException('Eskiz login failed: ${res.statusCode}');
    }
    final data = (jsonDecode(res.body) as Map)['data'] as Map;
    return _token = data['token'] as String;
  }

  @override
  Future<void> send(String phoneE164, String text) async {
    Future<http.Response> post(String token) => _client.post(
      _base.resolve('message/sms/send'),
      headers: {'authorization': 'Bearer $token'},
      body: {
        'mobile_phone': phoneE164.substring(1), // 998901234567, no plus
        'message': text,
        'from': from,
      },
    );

    var res = await post(_token ?? await _login());
    if (res.statusCode == 401) res = await post(await _login());
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException(
        'Eskiz send to ${maskPhone(phoneE164)} failed: ${res.statusCode}',
      );
    }
  }
}
