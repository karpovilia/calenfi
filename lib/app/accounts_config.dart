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

String _providerName(ProviderType p) => switch (p) {
      ProviderType.google => 'google',
      ProviderType.graph => 'graph',
      ProviderType.caldav => 'caldav',
      ProviderType.ews => 'ews',
    };

Map<String, dynamic> _accountToJson(Account a) {
  final cfg = <String, dynamic>{
    if (a.config.ewsUrl != null) 'ewsUrl': a.config.ewsUrl,
    if (a.config.caldavHost != null) 'caldavHost': a.config.caldavHost,
    if (a.config.caldavPort != null) 'caldavPort': a.config.caldavPort,
    if (a.config.caldavPrincipalPath != null)
      'caldavPrincipalPath': a.config.caldavPrincipalPath,
    if (a.config.scopes.isNotEmpty) 'scopes': a.config.scopes,
  };
  return {
    'id': a.id,
    'provider': _providerName(a.provider),
    'displayName': a.displayName,
    'email': a.email,
    if (cfg.isNotEmpty) 'config': cfg,
  };
}

/// Перезаписывает `accounts.json` (в конфиг-каталоге, вне дерева проекта).
/// Секреты сюда НЕ пишутся — только метаданные учётных записей.
Future<void> saveConfiguredAccounts(List<Account> accounts) async {
  final file = File(accountsConfigPath());
  await file.parent.create(recursive: true);
  final json = const JsonEncoder.withIndent('  ')
      .convert(accounts.map(_accountToJson).toList());
  await file.writeAsString('$json\n');
}

/// Добавляет/обновляет учётную запись в `accounts.json` (по `id`).
Future<void> addConfiguredAccount(Account a) async {
  final list = loadConfiguredAccounts().where((x) => x.id != a.id).toList()
    ..add(a);
  await saveConfiguredAccounts(list);
}

/// Убирает учётную запись из `accounts.json` (при удалении в UI).
Future<void> removeConfiguredAccount(String id) async {
  final list = loadConfiguredAccounts().where((x) => x.id != id).toList();
  await saveConfiguredAccounts(list);
}

/// Свободный идентификатор аккаунта для нового подключения (`acc-google`,
/// `acc-google-2`, …) — стабильный префикс по провайдеру + суффикс при коллизии.
String freeAccountId(ProviderType provider, {Iterable<String> taken = const []}) {
  final base = 'acc-${_providerName(provider)}';
  final used = taken.toSet();
  if (!used.contains(base)) return base;
  for (var i = 2; i < 1000; i++) {
    final id = '$base-$i';
    if (!used.contains(id)) return id;
  }
  return '$base-${used.length}';
}
