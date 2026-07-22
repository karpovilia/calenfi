import 'enums.dart';
import 'refresh_policy.dart';

/// Параметры подключения, специфичные для провайдера.
///
/// Намеренно «мешок» опциональных полей: для CalDAV — host/port/principal
/// (Yandex на :8443, FR-A3), для EWS — ewsUrl (FR-A4), для OAuth — scopes.
/// Секреты (токены/пароли) сюда НЕ кладём — они в SecureStore.
class AccountConfig {
  const AccountConfig({
    this.ewsUrl,
    this.caldavHost,
    this.caldavPort,
    this.caldavPrincipalPath,
    this.scopes = const [],
    this.extra = const {},
  });

  // EWS (Exchange)
  final String? ewsUrl;

  // CalDAV / CardDAV
  final String? caldavHost;
  final int? caldavPort;
  final String? caldavPrincipalPath;

  // OAuth
  final List<String> scopes;

  /// Прочие провайдер-специфичные параметры.
  final Map<String, String> extra;

  AccountConfig copyWith({
    String? ewsUrl,
    String? caldavHost,
    int? caldavPort,
    String? caldavPrincipalPath,
    List<String>? scopes,
    Map<String, String>? extra,
  }) =>
      AccountConfig(
        ewsUrl: ewsUrl ?? this.ewsUrl,
        caldavHost: caldavHost ?? this.caldavHost,
        caldavPort: caldavPort ?? this.caldavPort,
        caldavPrincipalPath: caldavPrincipalPath ?? this.caldavPrincipalPath,
        scopes: scopes ?? this.scopes,
        extra: extra ?? this.extra,
      );
}

/// Подключённая учётная запись (FR-A1).
class Account {
  const Account({
    required this.id,
    required this.provider,
    required this.displayName,
    required this.email,
    this.config = const AccountConfig(),
    this.refresh = const RefreshPolicy(),
    this.status = AccountStatus.ok,
    this.lastSyncUtc,
    this.lastError,
  });

  /// Локальный UUID (не провайдерный).
  final String id;
  final ProviderType provider;
  final String displayName;
  final String email;
  final AccountConfig config;
  final RefreshPolicy refresh;
  final AccountStatus status;

  /// Когда в последний раз УСПЕШНО синхронизировался (для плашки «не обновлялось с …»).
  final DateTime? lastSyncUtc;

  /// Текст последней ошибки синка (для плашки).
  final String? lastError;

  bool get isHealthy => status == AccountStatus.ok;

  Account copyWith({
    String? displayName,
    String? email,
    AccountConfig? config,
    RefreshPolicy? refresh,
    AccountStatus? status,
    DateTime? lastSyncUtc,
    String? lastError,
  }) =>
      Account(
        id: id,
        provider: provider,
        displayName: displayName ?? this.displayName,
        email: email ?? this.email,
        config: config ?? this.config,
        refresh: refresh ?? this.refresh,
        status: status ?? this.status,
        lastSyncUtc: lastSyncUtc ?? this.lastSyncUtc,
        lastError: lastError ?? this.lastError,
      );
}
