import 'package:drift/drift.dart';

import '../local/db/database.dart';

/// Справочник контактов (FR-K): автодополнение участников при создании встречи.
class ContactRepository {
  ContactRepository(this._db);
  final AppDatabase _db;

  Stream<List<ContactRow>> watchAll() =>
      (_db.select(_db.contacts)..orderBy([(c) => OrderingTerm(expression: c.displayName)]))
          .watch();

  Future<List<ContactRow>> all() =>
      (_db.select(_db.contacts)..orderBy([(c) => OrderingTerm(expression: c.displayName)]))
          .get();

  /// Поиск по имени/почте (для автодополнения).
  Future<List<ContactRow>> search(String q) async {
    final like = '%${q.toLowerCase()}%';
    return (_db.select(_db.contacts)
          ..where((c) =>
              c.displayName.lower().like(like) | c.email.lower().like(like))
          ..limit(20))
        .get();
  }

  /// Добавить/обновить контакт. id по умолчанию — нормализованная почта.
  Future<void> upsert({
    required String email,
    required String displayName,
    String? id,
    String source = 'manual',
  }) {
    return _db.into(_db.contacts).insertOnConflictUpdate(ContactsCompanion(
          id: Value(id ?? email.toLowerCase()),
          displayName: Value(displayName),
          email: Value(email),
          source: Value(source),
        ));
  }

  /// Добавить контакт, ТОЛЬКО если такого ещё нет (по id = нормализованная
  /// почта). Не затирает вручную добавленные/импортированные контакты с
  /// хорошими именами. Используется для автопополнения из участников встреч.
  Future<void> addIfAbsent({
    required String email,
    required String displayName,
    String source = 'event',
  }) {
    return _db.into(_db.contacts).insert(
          ContactsCompanion(
            id: Value(email.toLowerCase()),
            displayName: Value(displayName),
            email: Value(email),
            source: Value(source),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> delete(String id) =>
      (_db.delete(_db.contacts)..where((c) => c.id.equals(id))).go();
}
