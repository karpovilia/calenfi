// Регрессионный тест бага «кнопка синка отправляла только первое перенесённое
// событие» (июль 2026): applyAll делал enqueue+sync ПО ОДНОМУ событию, синк
// первого читал снапшот Outbox без остальных (и/или склеивался с фоновым
// синком) — второе событие «висело»/сбрасывалось. Контракт после фикса:
// к моменту старта синка ВСЕ ожидающие правки уже лежат в Outbox, синк один.

import 'package:calenfi/data/local/db/database.dart';
import 'package:calenfi/data/providers/calendar/mock/mock_provider.dart';
import 'package:calenfi/data/providers/calendar/provider_registry.dart';
import 'package:calenfi/data/repositories/account_repository.dart';
import 'package:calenfi/data/repositories/event_repository.dart';
import 'package:calenfi/domain/models/calendar_event.dart';
import 'package:calenfi/features/calendar/pending_edits.dart';
import 'package:calenfi/sync/sync_engine.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// SyncEngine-шпион: не ходит в сеть, а записывает, сколько заданий лежало в
/// Outbox в момент КАЖДОГО вызова синка.
class _RecordingSync extends SyncEngine {
  _RecordingSync(
      {required super.registry,
      required super.accounts,
      required super.events,
      required this.eventsRepo});
  final EventRepository eventsRepo;
  final outboxAtSync = <int>[];

  @override
  Future<List<AccountSyncReport>> syncAll() async {
    outboxAtSync.add((await eventsRepo.pendingOutbox()).length);
    return const [];
  }

  @override
  Future<AccountSyncReport> syncAccountById(String id) async {
    outboxAtSync.add((await eventsRepo.pendingOutbox()).length);
    return AccountSyncReport(id);
  }
}

void main() {
  late AppDatabase db;
  late EventRepository events;
  late _RecordingSync sync;
  late PendingEditsNotifier pending;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    events = EventRepository(db);
    sync = _RecordingSync(
      registry: ProviderRegistry(overrideFactory: (a) => MockProvider(a.id)),
      accounts: AccountRepository(db),
      events: events,
      eventsRepo: events,
    );
    pending = PendingEditsNotifier(events, sync);
  });
  tearDown(() async {
    pending.dispose();
    await db.close();
  });

  CalendarEvent ev(String id) => CalendarEvent(
        id: id,
        calendarId: 'acc-a|cal-1',
        title: 'Встреча $id',
        startUtc: DateTime.utc(2030, 1, 1, 10),
        endUtc: DateTime.utc(2030, 1, 1, 11),
        source: const EventSource(accountId: 'acc-a', calendarId: 'acc-a|cal-1'),
      );

  test('applyAll: сперва ВСЕ правки в Outbox, потом ровно один синк', () async {
    // Два перенесённых события ждут таймера (commitDelay > 0).
    await pending.stage(ev('e1'), const Duration(minutes: 2));
    await pending.stage(ev('e2'), const Duration(minutes: 2));
    expect(pending.state, hasLength(2));
    expect(await events.pendingOutbox(), isEmpty); // ещё не в очереди

    await pending.applyAll();

    // Один вызов синка, и в его момент в Outbox уже ОБА задания.
    expect(sync.outboxAtSync, [2],
        reason: 'синк по одному терял второе перенесённое событие');
    expect(pending.state, isEmpty);
  });

  test('applyAll без ожидающих правок — синк не дёргается', () async {
    await pending.applyAll();
    expect(sync.outboxAtSync, isEmpty);
  });
}
