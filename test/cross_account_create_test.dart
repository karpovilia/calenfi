// Регрессионный тест бага «событие создалось в чужом аккаунте» (июль 2026):
// outbox-задание create с calendarId аккаунта A обрабатывалось проходом синка
// аккаунта B, и из-за `orElse → cals.first` provider.createEvent вызывался на
// B — реальные встречи (теннис karpovinter) появлялись в рабочем O365 с чужим
// организатором. Guard: чужое create-задание пропускается и остаётся в
// очереди для своего аккаунта.

import 'package:calenfi/data/local/db/database.dart';
import 'package:calenfi/data/providers/calendar/mock/mock_provider.dart';
import 'package:calenfi/data/providers/calendar/provider_registry.dart';
import 'package:calenfi/data/repositories/account_repository.dart';
import 'package:calenfi/data/repositories/event_repository.dart';
import 'package:calenfi/domain/models/account.dart';
import 'package:calenfi/domain/models/calendar.dart';
import 'package:calenfi/domain/models/calendar_event.dart';
import 'package:calenfi/domain/models/enums.dart';
import 'package:calenfi/sync/sync_engine.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// MockProvider, записывающий все вызовы createEvent (кто и что создавал).
class _SpyProvider extends MockProvider {
  _SpyProvider(super.accountId, this.createdLog);
  final List<String> createdLog; // 'accId:eventId'

  @override
  Future<CalendarEvent> createEvent(
      Account acc, Calendar cal, CalendarEvent e) {
    createdLog.add('${acc.id}:${e.id}');
    return super.createEvent(acc, cal, e);
  }
}

void main() {
  late AppDatabase db;
  late AccountRepository accounts;
  late EventRepository events;
  late SyncEngine engine;
  final created = <String>[];

  const accA = Account(
      id: 'acc-a', provider: ProviderType.google, displayName: 'A', email: 'a@x.com');
  const accB = Account(
      id: 'acc-b', provider: ProviderType.graph, displayName: 'B', email: 'b@y.com');

  setUp(() async {
    created.clear();
    db = AppDatabase(NativeDatabase.memory());
    accounts = AccountRepository(db);
    events = EventRepository(db);
    engine = SyncEngine(
      registry:
          ProviderRegistry(overrideFactory: (a) => _SpyProvider(a.id, created)),
      accounts: accounts,
      events: events,
    );
    await accounts.upsertAccount(accA);
    await accounts.upsertAccount(accB);
    // первый синк заводит календари обоих аккаунтов
    await engine.syncAccount(accA);
    await engine.syncAccount(accB);
    created.clear();
  });
  tearDown(() => db.close());

  Future<CalendarEvent> stageCreateFor(Account acc) async {
    final cal = (await accounts.calendarsOf(acc.id)).first;
    final e = CalendarEvent(
      id: 'local-uuid-1', // локальный UUID до пуша
      calendarId: cal.id,
      title: 'Теннис',
      startUtc: DateTime.utc(2030, 1, 1, 10),
      endUtc: DateTime.utc(2030, 1, 1, 11),
      source: EventSource(accountId: acc.id, calendarId: cal.id),
    );
    await events.putLocalDirty(e);
    await events.enqueue('create', e.id);
    return e;
  }

  test('синк ЧУЖОГО аккаунта не создаёт событие и не трогает задание',
      () async {
    await stageCreateFor(accA);

    await engine.syncAccount(accB); // проход B по общему outbox

    // B ничего не создал…
    expect(created.where((c) => c.startsWith('acc-b:')), isEmpty,
        reason: 'создание в чужом аккаунте — порча данных (баг «теннис в c2m»)');
    // …и задание осталось в очереди для A.
    expect(await events.pendingOutbox(), hasLength(1));
  });

  test('свой аккаунт создаёт событие и очищает очередь', () async {
    await stageCreateFor(accA);

    await engine.syncAccount(accA);

    expect(created.where((c) => c.startsWith('acc-a:')), hasLength(1));
    expect(await events.pendingOutbox(), isEmpty);
  });
}
