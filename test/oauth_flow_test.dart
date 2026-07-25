// Тест OAuth authorization-code + PKCE через loopback: без реального браузера и
// без сетевых зависимостей. Колбэк launch играет роль браузера (редиректит на
// loopback с кодом), а token-endpoint — настоящий локальный HttpServer.
// Проверяем: PKCE-параметры уходят, code меняется на токены, state сверяется.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:calenfi/data/secure/oauth_flow.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer tokenServer;
  Map<String, String>? tokenForm;

  setUp(() async {
    tokenForm = null;
    tokenServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    tokenServer.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      tokenForm = Uri.splitQueryString(body);
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'access_token': 'AT-123',
          'refresh_token': 'RT-456',
          'expires_in': 3600,
        }));
      await req.response.close();
    });
  });
  tearDown(() => tokenServer.close(force: true));

  String tokenUrl() => 'http://localhost:${tokenServer.port}/token';

  test('loopback-флоу: code → токены, PKCE и state корректны', () async {
    Uri? seenAuthUrl;
    Future<void> fakeLaunch(Uri authUrl) async {
      seenAuthUrl = authUrl;
      final redirect = Uri.parse(authUrl.queryParameters['redirect_uri']!);
      final state = authUrl.queryParameters['state']!;
      final probe = Dio();
      unawaited(probe.getUri(
        redirect.replace(queryParameters: {'code': 'CODE-789', 'state': state}),
        options: Options(validateStatus: (_) => true),
      ));
    }

    final res = await OAuthFlow().run(
      authorizationEndpoint: 'https://auth.example/authorize',
      tokenEndpoint: tokenUrl(),
      clientId: 'client-abc',
      clientSecret: 'secret-xyz',
      scopes: const ['openid', 'calendar'],
      launch: fakeLaunch,
    );

    expect(res.accessToken, 'AT-123');
    expect(res.refreshToken, 'RT-456');

    expect(seenAuthUrl!.queryParameters['code_challenge_method'], 'S256');
    expect(seenAuthUrl!.queryParameters['code_challenge'], isNotEmpty);
    expect(seenAuthUrl!.queryParameters['scope'], 'openid calendar');
    expect(seenAuthUrl!.queryParameters['redirect_uri'],
        startsWith('http://localhost:'));

    expect(tokenForm!['grant_type'], 'authorization_code');
    expect(tokenForm!['code'], 'CODE-789');
    expect(tokenForm!['client_secret'], 'secret-xyz');
    expect((tokenForm!['code_verifier'] ?? '').length,
        greaterThanOrEqualTo(43));
  });

  test('несовпадение state → ошибка (защита от CSRF)', () async {
    Future<void> badLaunch(Uri authUrl) async {
      final redirect = Uri.parse(authUrl.queryParameters['redirect_uri']!);
      final probe = Dio();
      unawaited(probe.getUri(
        redirect.replace(queryParameters: {'code': 'X', 'state': 'WRONG'}),
        options: Options(validateStatus: (_) => true),
      ));
    }

    await expectLater(
      OAuthFlow().run(
        authorizationEndpoint: 'https://auth.example/authorize',
        tokenEndpoint: tokenUrl(),
        clientId: 'c',
        scopes: const ['x'],
        launch: badLaunch,
      ),
      throwsA(isA<OAuthException>()),
    );
  });
}
