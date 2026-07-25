import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/accounts_config.dart';
import '../../app/providers.dart';
import '../../data/providers/calendar/google/google_token.dart';
import '../../data/providers/calendar/graph/graph_token.dart';
import '../../data/secure/credential_source.dart';
import '../../data/secure/oauth_flow.dart';
import '../../data/secure/secret_store.dart';
import '../../domain/models/account.dart';
import '../../domain/models/enums.dart';

/// Подключение реальных учётных записей из приложения: OAuth (Google/Microsoft)
/// и парольные провайдеры (Yandex CalDAV / Exchange EWS). Сохраняет секреты в
/// keyring, метаданные — в `accounts.json`, заводит аккаунт в БД и синкает.
class ConnectAccountService {
  ConnectAccountService(this.ref);
  final Ref ref;

  static const _googleAuth = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const _googleToken = 'https://oauth2.googleapis.com/token';
  static const _googleScopes = [
    'openid',
    'email',
    'https://www.googleapis.com/auth/calendar',
    'https://www.googleapis.com/auth/meetings.space.created',
  ];
  static const _graphScopes = [
    'openid',
    'email',
    'offline_access',
    'https://graph.microsoft.com/Calendars.ReadWrite',
    'https://graph.microsoft.com/OnlineMeetings.ReadWrite',
  ];

  Future<void> _openBrowser(Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw OAuthException('не удалось открыть браузер для входа');
    }
  }

  /// Подключить Google-аккаунт: OAuth → сохранить refresh-токен в keyring →
  /// завести аккаунт. Возвращает адрес подключённого ящика.
  Future<String> connectGoogle() async {
    final creds = CredentialSource.load();
    final clientId = creds.googleClientId;
    final clientSecret = creds.googleClientSecret;
    if (clientId == null || clientSecret == null) {
      throw OAuthException(
          'Google OAuth не настроен: задайте GOOGLE_OAUTH_CLIENT_ID и '
          'GOOGLE_OAUTH_CLIENT_SECRET (Google Cloud → OAuth client, тип Desktop).');
    }
    final dio = Dio();
    final res = await OAuthFlow(dio: dio).run(
      authorizationEndpoint: _googleAuth,
      tokenEndpoint: _googleToken,
      clientId: clientId,
      clientSecret: clientSecret,
      scopes: _googleScopes,
      extraAuthParams: const {'access_type': 'offline', 'prompt': 'consent'},
      launch: _openBrowser,
    );
    if (res.refreshToken == null) {
      throw OAuthException(
          'Google не выдал refresh-токен — повторите вход (нужно согласие).');
    }
    final email = await _googleEmail(dio, res.accessToken);

    // Формат google.oauth2 Credentials — как читает GoogleToken.loadFor.
    await SecretStore.instance.write(
      GoogleToken.secretKey(email),
      jsonEncode({
        'token': res.accessToken,
        'refresh_token': res.refreshToken,
        'token_uri': _googleToken,
        'client_id': clientId,
        'client_secret': clientSecret,
        'scopes': _googleScopes,
      }),
    );
    await _finishAccount(ProviderType.google, email, 'Google — ${_local(email)}');
    return email;
  }

  /// Подключить Microsoft 365 / Outlook: OAuth (public client, PKCE) →
  /// сохранить refresh-токен → завести аккаунт.
  Future<String> connectMicrosoft() async {
    final creds = CredentialSource.load();
    final clientId = creds.graphClientId;
    if (clientId == null) {
      throw OAuthException(
          'Microsoft OAuth не настроен: задайте GRAPH_CLIENT_ID (Azure → '
          'регистрация приложения, платформа «Mobile and desktop», redirect '
          'http://localhost).');
    }
    final tenant = creds.graphTenant;
    final base = 'https://login.microsoftonline.com/$tenant/oauth2/v2.0';
    final dio = Dio();
    final res = await OAuthFlow(dio: dio).run(
      authorizationEndpoint: '$base/authorize',
      tokenEndpoint: '$base/token',
      clientId: clientId,
      scopes: _graphScopes,
      extraAuthParams: const {'prompt': 'select_account'},
      launch: _openBrowser,
    );
    if (res.refreshToken == null) {
      throw OAuthException('Microsoft не выдал refresh-токен — повторите вход.');
    }
    final email = await _graphEmail(dio, res.accessToken);

    await SecretStore.instance.write(
      GraphToken.secretKey(email),
      jsonEncode({
        'client_id': clientId,
        'tenant': tenant,
        'access_token': res.accessToken,
        'refresh_token': res.refreshToken,
        'scopes': _graphScopes,
      }),
    );
    await _finishAccount(ProviderType.graph, email, 'Office 365 — ${_local(email)}');
    return email;
  }

  /// Подключить CalDAV (Yandex и совместимые) по паролю приложения.
  Future<void> connectCaldav({
    required String email,
    required String appPassword,
    required String host,
    int port = 8443,
  }) async {
    await SecretStore.instance
        .write(CredentialSource.caldavPasswordVar(email), appPassword);
    final acc = _account(
      ProviderType.caldav,
      email,
      'CalDAV — ${_local(email)}',
      config: AccountConfig(
        caldavHost: host,
        caldavPort: port,
        caldavPrincipalPath: '/principals/users/$email/',
      ),
    );
    await _persist(acc);
  }

  /// Подключить Exchange (EWS) по паролю. [ewsUrl] опционален (иначе
  /// autodiscover); [user] — если логин отличается от e-mail (DOMAIN\\user).
  Future<void> connectEws({
    required String email,
    required String password,
    String? ewsUrl,
    String? user,
  }) async {
    await SecretStore.instance
        .write(CredentialSource.ewsPasswordVar(email), password);
    if (ewsUrl != null && ewsUrl.isNotEmpty) {
      await SecretStore.instance
          .write('${CredentialSource.keyFor(email)}_EWS_URL', ewsUrl);
    }
    if (user != null && user.isNotEmpty) {
      await SecretStore.instance
          .write('${CredentialSource.keyFor(email)}_EWS_USER', user);
    }
    final acc = _account(ProviderType.ews, email, 'Exchange — ${_local(email)}',
        config: AccountConfig(ewsUrl: ewsUrl));
    await _persist(acc);
  }

  // ───────────────────────── helpers ─────────────────────────

  Future<String> _googleEmail(Dio dio, String accessToken) async {
    final r = await dio.get('https://www.googleapis.com/oauth2/v3/userinfo',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}));
    final email = (r.data as Map)['email'];
    if (email is! String || email.isEmpty) {
      throw OAuthException('не удалось получить адрес Google-аккаунта');
    }
    return email;
  }

  Future<String> _graphEmail(Dio dio, String accessToken) async {
    final r = await dio.get('https://graph.microsoft.com/v1.0/me',
        queryParameters: {r'$select': 'mail,userPrincipalName'},
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}));
    final m = r.data as Map;
    final email = (m['mail'] ?? m['userPrincipalName']);
    if (email is! String || email.isEmpty) {
      throw OAuthException('не удалось получить адрес Microsoft-аккаунта');
    }
    return email;
  }

  String _local(String email) => email.split('@').first;

  Account _account(ProviderType provider, String email, String displayName,
      {AccountConfig config = const AccountConfig()}) {
    final taken =
        (ref.read(accountsStreamProvider).value ?? const <Account>[])
            .map((a) => a.id);
    // Один и тот же ящик уже подключён? Переиспользуем его id (переподключение).
    final existing =
        (ref.read(accountsStreamProvider).value ?? const <Account>[])
            .where((a) => a.email == email && a.provider == provider)
            .firstOrNull;
    return Account(
      id: existing?.id ?? freeAccountId(provider, taken: taken),
      provider: provider,
      displayName: displayName,
      email: email,
      config: config,
    );
  }

  Future<void> _finishAccount(
      ProviderType provider, String email, String displayName) async {
    await _persist(_account(provider, email, displayName));
  }

  /// Сохранить аккаунт в БД + accounts.json, пересоздать провайдеры и синкнуть.
  Future<void> _persist(Account acc) async {
    await ref.read(accountRepositoryProvider).upsertAccount(acc);
    await addConfiguredAccount(acc);
    ref.invalidate(providerRegistryProvider);
    await ref.read(syncEngineProvider).syncAccount(acc);
  }
}

final connectAccountServiceProvider =
    Provider<ConnectAccountService>((ref) => ConnectAccountService(ref));
