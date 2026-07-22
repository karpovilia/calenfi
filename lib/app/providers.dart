import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/db/database_provider.dart';
import '../data/providers/calendar/provider_registry.dart';
import '../data/local/db/database.dart';
import '../data/repositories/account_repository.dart';
import '../data/repositories/contact_repository.dart';
import '../data/repositories/event_repository.dart';
import '../domain/models/account.dart';
import '../domain/models/calendar.dart';
import '../sync/sync_engine.dart';

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepository(ref.watch(databaseProvider));
});

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return AccountRepository(ref.watch(databaseProvider));
});

final providerRegistryProvider = Provider<ProviderRegistry>((ref) {
  return ProviderRegistry();
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine(
    registry: ref.watch(providerRegistryProvider),
    accounts: ref.watch(accountRepositoryProvider),
    events: ref.watch(eventRepositoryProvider),
    contacts: ref.watch(contactRepositoryProvider),
  );
});

final accountsStreamProvider = StreamProvider<List<Account>>((ref) {
  return ref.watch(accountRepositoryProvider).watchAccounts();
});

final calendarsStreamProvider = StreamProvider<List<Calendar>>((ref) {
  return ref.watch(accountRepositoryProvider).watchCalendars();
});

final contactRepositoryProvider = Provider<ContactRepository>((ref) {
  return ContactRepository(ref.watch(databaseProvider));
});

/// Справочник контактов (FR-K) для автодополнения участников.
final contactsStreamProvider = StreamProvider<List<ContactRow>>((ref) {
  return ref.watch(contactRepositoryProvider).watchAll();
});

/// Колбэк ручной синхронизации (FR-S3).
final syncTriggerProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    await ref.read(syncEngineProvider).syncAll();
  };
});

/// Регулярная автосинхронизация по индивидуальному расписанию каждого аккаунта
/// (FR-A10/FR-S2). Тикаем раз в минуту и синкаем те аккаунты, у которых истёк
/// их интервал (`RefreshPolicy.effectiveInterval`; `manual` → не автосинкается).
/// Watch'ить в корне App. Без неё календарь обновлялся только при старте/кнопке.
final periodicSyncProvider = Provider<void>((ref) {
  final engine = ref.read(syncEngineProvider);
  final accountsRepo = ref.read(accountRepositoryProvider);
  final timer = Timer.periodic(const Duration(minutes: 1), (_) async {
    final all = await accountsRepo.allAccounts();
    final now = DateTime.now().toUtc();
    for (final a in all) {
      final interval = a.refresh.effectiveInterval;
      if (interval == Duration.zero) continue; // ручной режим
      final last = a.lastSyncUtc;
      if (last == null || now.difference(last) >= interval) {
        engine.syncAccount(a); // fire-and-forget, ошибки изолированы
      }
    }
  });
  ref.onDispose(timer.cancel);
});
