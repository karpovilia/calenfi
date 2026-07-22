import 'dart:convert';

import 'package:calenfi/data/secure/credential_source.dart';
import 'package:calenfi/data/secure/secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Бэкенд в памяти: имитирует системный keyring без обращения к ОС.
class _FakeBackend extends KeyringBackend {
  _FakeBackend({this.broken = false});

  /// «Сломанный» keyring: запись проходит, но прочитать нечего — так ведёт себя
  /// демон, который не умеет искать по атрибутам (например KeePassXC).
  final bool broken;
  String? blob;

  @override
  Future<String?> read() async => broken ? null : blob;

  @override
  Future<void> write(String value) async => blob = value;
}

void main() {
  group('SecretStore', () {
    // Фолбэк тоже в памяти: тесты не должны читать/писать реальный
    // ~/.config/calenfi/secrets.json пользователя.
    late _FakeBackend fallback;
    setUp(() {
      fallback = _FakeBackend();
      SecretStore.fallbackBackend = fallback;
    });

    test('читает секреты из бэкенда в синхронный кеш', () async {
      final b = _FakeBackend()
        ..blob = jsonEncode({'ME_EXAMPLE_COM_CALDAV_PASSWORD': 'p@ss'});
      SecretStore.backend = b;
      await SecretStore.instance.warmUp(force: true);

      expect(SecretStore.instance.value('ME_EXAMPLE_COM_CALDAV_PASSWORD'), 'p@ss');
      expect(CredentialSource.load().caldavPassword('me@example.com'), 'p@ss');
    });

    test('write пишет и в кеш, и в бэкенд', () async {
      final b = _FakeBackend()..blob = '{}';
      SecretStore.backend = b;
      await SecretStore.instance.warmUp(force: true);

      await SecretStore.instance.write('ZOOM_CLIENT_ID', 'abc');
      expect(SecretStore.instance.value('ZOOM_CLIENT_ID'), 'abc');
      expect(jsonDecode(b.blob!)['ZOOM_CLIENT_ID'], 'abc');
    });

    test('пустое значение читается как null', () async {
      SecretStore.backend = _FakeBackend()..blob = jsonEncode({'K': ''});
      await SecretStore.instance.warmUp(force: true);
      expect(SecretStore.instance.value('K'), isNull);
    });

    test('битый JSON не роняет старт', () async {
      SecretStore.backend = _FakeBackend()..blob = 'not json';
      await SecretStore.instance.warmUp(force: true);
      expect(SecretStore.instance.all, isEmpty);
    });

    test('нерабочий keyring → переключение на файловый фолбэк', () async {
      SecretStore.backend = _FakeBackend(broken: true);
      await SecretStore.instance.warmUp(force: true);
      expect(SecretStore.instance.usesKeyring, isFalse);
    });

    test('ключи токенов совпадают с именами legacy-файлов', () {
      expect(SecretStore.tokenKey('gcal_ME_GMAIL_COM'), 'token:gcal_ME_GMAIL_COM');
    });
  });
}
