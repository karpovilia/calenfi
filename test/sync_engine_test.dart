import 'package:calenfi/data/local/db/database.dart';
import 'package:calenfi/data/providers/calendar/mock/mock_provider.dart';
import 'package:calenfi/data/providers/calendar/provider_registry.dart';
import 'package:calenfi/data/repositories/account_repository.dart';
import 'package:calenfi/data/repositories/event_repository.dart';
import 'package:calenfi/domain/models/account.dart';
import 'package:calenfi/domain/models/calendar_event.dart';
import 'package:calenfi/domain/models/enums.dart';
import 'package:calenfi/domain/providers/calendar_provider.dart';
import 'package:calenfi/sync/sync_engine.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late AccountRepository accounts;
  late EventRepository events;
  late SyncEngine engine;

  const acc = Account(
    id: 'a', provider: ProviderType.google, displayName: 'A', email: 'a@x.com');

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    accounts = AccountRepository(db);
    events = EventRepository(db);
    engine = SyncEngine(
      registry: ProviderRegistry(overrideFactory: (a) => MockProvider(a.id)),
      accounts: accounts,
      events: events,
    );
  });
  tearDown(() => db.close());

  // широкий диапазон вокруг "сейчас" (мок сеет события на сегодня/завтра)
  DateRange wide() {
    final now = DateTime.now().toUtc();
    return DateRange(now.subtract(const Duration(days: 7)),
        now.add(const Duration(days: 14)));
  }

  group('SyncEngine', () {
    test('первый синк создаёт календари и подтягивает события', () async {
      await accounts.upsertAccount(acc);
      final report = await engine.syncAccount(acc);

      expect(report.ok, isTrue);
      expect((await accounts.calendarsOf('a')).isNotEmpty, isTrue);

      final merged = await events.watchMerged(wide()).first;
      expect(merged, isNotEmpty);
    });

    test('Outbox: локальное создание досылается и очищает очередь', () async {
      await accounts.upsertAccount(acc);
      await engine.syncAccount(acc); // создаст календари

      final cal = (await accounts.calendarsOf('a')).first;
      final e = CalendarEvent(
        id: 'local-1',
        calendarId: cal.id,
        title: 'Локальное событие',
        startUtc: DateTime.now().toUtc(),
        endUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
        source: EventSource(accountId: 'a', calendarId: cal.id),
      );
      await events.putLocalDirty(e);
      await events.enqueue('create', e.id);

      expect((await events.pendingOutbox()).length, 1);
      await engine.syncAccount(acc);
      expect((await events.pendingOutbox()), isEmpty);
    });

    test('повторный синк не дублирует события (upsert)', () async {
      await accounts.upsertAccount(acc);
      await engine.syncAccount(acc);
      final first = (await events.watchMerged(wide()).first).length;
      await engine.syncAccount(acc);
      final second = (await events.watchMerged(wide()).first).length;
      expect(second, first);
    });
  });
}
