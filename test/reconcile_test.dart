import 'package:calenfi/data/local/db/database.dart';
import 'package:calenfi/data/repositories/event_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late EventRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = EventRepository(db);
  });
  tearDown(() => db.close());

  Future<void> add(String id, DateTime start, {bool dirty = false}) async {
    await db.into(db.events).insert(EventsCompanion.insert(
          id: id, calendarId: 'cal', accountId: 'a', title: id,
          startUtc: start, endUtc: start.add(const Duration(hours: 1)),
          dirty: Value(dirty),
        ));
  }

  Future<Set<String>> ids() async =>
      (await db.select(db.events).get()).map((e) => e.id).toSet();

  final winStart = DateTime.utc(2026, 6, 1);
  final winEnd = DateTime.utc(2026, 7, 1);

  group('reconcileWindow (удаление пропавших в источнике)', () {
    test('удаляет локальное событие в окне, которого нет в keepIds', () async {
      await add('keep', DateTime.utc(2026, 6, 10));
      await add('gone', DateTime.utc(2026, 6, 11)); // удалено в облаке
      await repo.reconcileWindow('cal', winStart, winEnd, {'keep'});
      expect(await ids(), {'keep'});
    });

    test('не трогает события вне окна', () async {
      await add('outside', DateTime.utc(2026, 8, 1)); // позже окна
      await repo.reconcileWindow('cal', winStart, winEnd, {});
      expect(await ids(), {'outside'});
    });

    test('не удаляет локальные несинхронизированные правки (dirty)', () async {
      await add('local-new', DateTime.utc(2026, 6, 15), dirty: true);
      await repo.reconcileWindow('cal', winStart, winEnd, {}); // источник пуст
      expect(await ids(), {'local-new'});
    });

    test('пустой keepIds очищает окно (календарь опустел в источнике)', () async {
      await add('a1', DateTime.utc(2026, 6, 5));
      await add('a2', DateTime.utc(2026, 6, 6));
      await repo.reconcileWindow('cal', winStart, winEnd, {});
      expect(await ids(), isEmpty);
    });
  });
}
