import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'accounts_config.dart';
import 'providers.dart';

/// Идемпотентно заводит недостающие аккаунты из пользовательского
/// `accounts.json` (быстро, локально), затем запускает синк **в фоне** (НЕ ждём
/// его) — UI показывается сразу из кэша Drift и обновляется реактивно по мере
/// прихода данных. Иначе старт висел бы на сетевой синхронизации всех аккаунтов
/// (особенно медленный EWS).
///
/// Файла нет → аккаунтов нет: приложение стартует пустым, учётные записи
/// добавляются пользователем (см. `docs/accounts.example.json`).
Future<void> bootstrap(WidgetRef ref) async {
  final accounts = ref.read(accountRepositoryProvider);
  final existing = (await accounts.allAccounts()).map((a) => a.id).toSet();

  for (final a in loadConfiguredAccounts()) {
    if (!existing.contains(a.id)) {
      await accounts.upsertAccount(a);
    }
  }

  // fire-and-forget: не блокируем первый кадр сетевым синком
  unawaited(ref.read(syncEngineProvider).syncAll());
}
