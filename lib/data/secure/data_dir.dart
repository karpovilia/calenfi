import 'dart:io';

/// Каталог данных приложения на мобиле (Android/iOS) и Windows, где лежит БД.
/// Выставляется один раз в `main()` из `getApplicationSupportDirectory()`.
/// На Linux/macOS остаётся null — там путь считается от домашнего каталога.
String? calenfiDataDir;

/// Каталог пользовательской конфигурации Calenfi (НЕ внутри дерева проекта):
///   Linux   — `$XDG_CONFIG_HOME/calenfi` (по умолчанию `~/.config/calenfi`)
///   macOS   — `~/Library/Application Support/calenfi`
///   Windows — каталог данных приложения или `%APPDATA%\calenfi`
///   мобила  — каталог данных приложения
///
/// Здесь живут `accounts.json` и legacy-файлы секретов до импорта в keyring.
String configDir() {
  if (calenfiDataDir != null) return calenfiDataDir!;
  final env = Platform.environment;
  final home = env['HOME'] ?? env['USERPROFILE'] ?? '.';
  if (Platform.isMacOS) return '$home/Library/Application Support/calenfi';
  if (Platform.isWindows) return '${env['APPDATA'] ?? home}\\calenfi';
  return '${env['XDG_CONFIG_HOME'] ?? '$home/.config'}/calenfi';
}

/// Файл со списком учётных записей (`accounts.json`). Личных данных в коде нет:
/// аккаунты заводит пользователь, пример — `docs/accounts.example.json`.
String accountsConfigPath() =>
    Platform.environment['CALENFI_ACCOUNTS'] ?? '${configDir()}/accounts.json';

/// Legacy-файл секретов (`KEY=value`) — читается **только для импорта** в keyring
/// при первом запуске. Путь: env `CALENFI_SECRETS` или `<config>/secrets.env`.
String legacySecretsPath() =>
    Platform.environment['CALENFI_SECRETS'] ?? '${configDir()}/secrets.env';

/// Legacy-каталог с OAuth-токенами (`gcal_*.json`, `graph_*.json`) — тоже только
/// для импорта. Путь: env `CALENFI_TOKENS` или `<config>/.tokens`.
String legacyTokensDir() =>
    Platform.environment['CALENFI_TOKENS'] ?? '${configDir()}/.tokens';
