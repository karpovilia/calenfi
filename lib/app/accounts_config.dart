import 'dart:convert';
import 'dart:io';

import '../data/secure/data_dir.dart';
import '../domain/models/account.dart';
import '../domain/models/enums.dart';

/// Учётные записи пользователя описываются файлом `accounts.json` в
/// конфиг-каталоге (см. [accountsConfigPath]) — в коде нет ни одного адреса.
/// Секреты туда НЕ кладутся: пароли и OAuth-токены живут в системном keyring
/// (см. `lib/data/secure/secret_store.dart`).
///
/// Формат (пример — `docs/accounts.example.json`):
/// ```json
/// [
///   {"id": "acc-google", "provider": "google",
///    "displayName": "Google", "email": "me@gmail.com"},
///   {"id": "acc-work", "provider": "caldav",
///    "displayName": "Work", "email": "me@example.org",
///    "config": {"caldavHost": "caldav.example.org", "caldavPort": 8443,
///               "caldavPrincipalPath": "/principals/users/me@example.org/"}}
/// ]
/// ```
List<Account> loadConfiguredAccounts() {
  final file = File(accountsConfigPath());
  if (!file.existsSync()) return const [];
  try {
    final raw = jsonDecode(file.readAsStringSync());
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map(_accountFromJson).toList();
  } on FormatException {
    return const [];
  }
}

Account _accountFromJson(Map<String, dynamic> m) {
  final cfg = (m['config'] as Map<String, dynamic>?) ?? const {};
  return Account(
    id: m['id'] as String,
    provider: _providerFromName(m['provider'] as String?),
    displayName: (m['displayName'] as String?) ?? (m['email'] as String),
    email: m['email'] as String,
    config: AccountConfig(
      ewsUrl: cfg['ewsUrl'] as String?,
      caldavHost: cfg['caldavHost'] as String?,
      caldavPort: (cfg['caldavPort'] as num?)?.toInt(),
      caldavPrincipalPath: cfg['caldavPrincipalPath'] as String?,
      scopes: ((cfg['scopes'] as List?) ?? const []).cast<String>(),
    ),
  );
}

ProviderType _providerFromName(String? name) => switch (name) {
      'google' => ProviderType.google,
      'graph' || 'o365' || 'office365' => ProviderType.graph,
      'caldav' => ProviderType.caldav,
      'ews' || 'exchange' => ProviderType.ews,
      _ => throw FormatException('неизвестный provider: $name'),
    };
