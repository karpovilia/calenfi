// Telemost-провижинер: с токеном создаёт встречу (POST /v1/conferences,
// Authorization: OAuth <token>), без токена — понятная ошибка. Реальный API
// заменён локальным HttpServer, base URL переопределяется тестовым хуком.

import 'dart:convert';
import 'dart:io';

import 'package:calenfi/data/providers/conference/conference_provisioner.dart';
import 'package:calenfi/data/secure/credential_source.dart';
import 'package:calenfi/domain/models/enums.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('без токена — ConferenceUnavailableException', () async {
    final prov = ConferenceProvisioner(
        credentials: CredentialSource.fromMap(const {}));
    await expectLater(
      prov.resolve(ConferenceType.telemost,
          target: null, allAccounts: const [],
          start: DateTime.utc(2030, 1, 1, 10),
          end: DateTime.utc(2030, 1, 1, 11),
          subject: 'X'),
      throwsA(isA<ConferenceUnavailableException>()),
    );
  });

  test('с токеном — создаёт встречу и шлёт OAuth-заголовок', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    String? auth;
    server.listen((req) async {
      auth = req.headers.value('authorization');
      await utf8.decoder.bind(req).join();
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'id': 'conf-1', 'join_url': 'https://telemost.yandex.ru/j/conf-1'}));
      await req.response.close();
    });
    addTearDown(() => server.close(force: true));

    final prov = ConferenceProvisioner(
      credentials:
          CredentialSource.fromMap(const {'TELEMOST_OAUTH_TOKEN': 'tok-123'}),
      dio: Dio(),
      telemostBaseUrl: 'http://localhost:${server.port}/v1/conferences',
    );
    final conf = await prov.resolve(ConferenceType.telemost,
        target: null, allAccounts: const [],
        start: DateTime.utc(2030, 1, 1, 10),
        end: DateTime.utc(2030, 1, 1, 11),
        subject: 'X');

    expect(conf.type, ConferenceType.telemost);
    expect(conf.joinUrl, 'https://telemost.yandex.ru/j/conf-1');
    expect(conf.meetingId, 'conf-1');
    expect(auth, 'OAuth tok-123');
  });
}
