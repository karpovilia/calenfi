import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/models/account.dart';
import '../../domain/models/calendar.dart' as dom;
import '../../domain/models/enums.dart';
import '../../domain/models/refresh_policy.dart';
import '../local/db/database.dart';

/// Доступ к учётным записям и календарям (FR-A).
class AccountRepository {
  AccountRepository(this._db);
  final AppDatabase _db;

  Stream<List<Account>> watchAccounts() =>
      _db.select(_db.accounts).watch().map((rows) => rows.map(_toAccount).toList());

  Future<List<Account>> allAccounts() async =>
      (await _db.select(_db.accounts).get()).map(_toAccount).toList();

  Stream<List<dom.Calendar>> watchCalendars() =>
      _db.select(_db.calendars).watch().map((r) => r.map(_toCalendar).toList());

  Future<List<dom.Calendar>> calendarsOf(String accountId) async {
    final rows = await (_db.select(_db.calendars)
          ..where((c) => c.accountId.equals(accountId)))
        .get();
    return rows.map(_toCalendar).toList();
  }

  Future<void> upsertAccount(Account a) =>
      _db.into(_db.accounts).insertOnConflictUpdate(AccountsCompanion(
            id: Value(a.id),
            provider: Value(a.provider),
            displayName: Value(a.displayName),
            email: Value(a.email),
            status: Value(a.status),
            configJson: Value(_encodeConfig(a.config)),
            refreshJson: Value(_encodeRefresh(a.refresh)),
          ));

  Future<void> upsertCalendars(List<dom.Calendar> cals) async {
    await _db.batch((b) {
      for (final c in cals) {
        b.insert(
          _db.calendars,
          CalendarsCompanion(
            id: Value(c.id),
            accountId: Value(c.accountId),
            name: Value(c.name),
            nameOverride: Value(c.nameOverride),
            color: Value(c.color),
            colorOverride: Value(c.colorOverride),
            defaultReminderMinutes: Value(c.defaultReminderMinutes),
            visible: Value(c.visible),
            syncState: Value(c.syncState),
            isPrimary: Value(c.isPrimary),
            readOnly: Value(c.readOnly),
          ),
          onConflict: DoUpdate((old) => CalendarsCompanion(
                name: Value(c.name),
                color: Value(c.color),
                // visible, colorOverride, defaultReminderMinutes —
                // пользовательские, синком не трогаем:
                isPrimary: Value(c.isPrimary),
                readOnly: Value(c.readOnly),
              )),
        );
      }
    });
  }

  Future<void> setCalendarVisible(String id, bool visible) =>
      (_db.update(_db.calendars)..where((c) => c.id.equals(id)))
          .write(CalendarsCompanion(visible: Value(visible)));

  /// Пользовательский цвет календаря (FR-A9). `null` — сброс к цвету источника.
  Future<void> setCalendarColor(String id, int? color) =>
      (_db.update(_db.calendars)..where((c) => c.id.equals(id)))
          .write(CalendarsCompanion(colorOverride: Value(color)));

  /// Пользовательское имя календаря (переименование). `null`/пусто — сброс к
  /// имени из источника.
  Future<void> setCalendarName(String id, String? name) =>
      (_db.update(_db.calendars)..where((c) => c.id.equals(id))).write(
          CalendarsCompanion(
              nameOverride:
                  Value((name != null && name.trim().isNotEmpty) ? name.trim() : null)));

  /// Дефолтное напоминание календаря (FR-N): минут до начала, 0 = в момент
  /// начала, `null` = без напоминания.
  Future<void> setCalendarDefaultReminder(String id, int? minutes) =>
      (_db.update(_db.calendars)..where((c) => c.id.equals(id)))
          .write(CalendarsCompanion(defaultReminderMinutes: Value(minutes)));

  Future<void> setCalendarSyncState(String id, String? state) =>
      (_db.update(_db.calendars)..where((c) => c.id.equals(id)))
          .write(CalendarsCompanion(syncState: Value(state)));

  Future<void> setAccountStatus(String id, AccountStatus s) =>
      (_db.update(_db.accounts)..where((a) => a.id.equals(id)))
          .write(AccountsCompanion(status: Value(s)));

  /// Расписание автообновления аккаунта (FR-A10).
  Future<void> setRefresh(String id, RefreshPolicy p) =>
      (_db.update(_db.accounts)..where((a) => a.id.equals(id)))
          .write(AccountsCompanion(refreshJson: Value(_encodeRefresh(p))));

  /// Успешный синк: статус ok, обновляем lastSync, чистим ошибку.
  Future<void> recordSyncSuccess(String id, DateTime when) =>
      (_db.update(_db.accounts)..where((a) => a.id.equals(id))).write(
          AccountsCompanion(
              status: const Value(AccountStatus.ok),
              lastSyncUtc: Value(when),
              lastError: const Value(null)));

  /// Неудачный синк (после ретраев): статус ошибки + текст; lastSync НЕ трогаем.
  Future<void> recordSyncFailure(
          String id, AccountStatus status, String error) =>
      (_db.update(_db.accounts)..where((a) => a.id.equals(id))).write(
          AccountsCompanion(status: Value(status), lastError: Value(error)));

  Future<void> deleteAccount(String id) async {
    await (_db.delete(_db.events)..where((e) => e.accountId.equals(id))).go();
    await (_db.delete(_db.calendars)..where((c) => c.accountId.equals(id))).go();
    await (_db.delete(_db.accounts)..where((a) => a.id.equals(id))).go();
  }

  // --- mapping ---

  Account _toAccount(AccountRow r) => Account(
        id: r.id,
        provider: r.provider,
        displayName: r.displayName,
        email: r.email,
        status: r.status,
        config: _decodeConfig(r.configJson),
        refresh: _decodeRefresh(r.refreshJson),
        lastSyncUtc: r.lastSyncUtc,
        lastError: r.lastError,
      );

  dom.Calendar _toCalendar(CalendarRow r) => dom.Calendar(
        id: r.id,
        accountId: r.accountId,
        name: r.name,
        nameOverride: r.nameOverride,
        color: r.color,
        colorOverride: r.colorOverride,
        defaultReminderMinutes: r.defaultReminderMinutes,
        visible: r.visible,
        syncState: r.syncState,
        isPrimary: r.isPrimary,
        readOnly: r.readOnly,
      );

  static String _encodeConfig(AccountConfig c) => jsonEncode({
        'ewsUrl': c.ewsUrl,
        'caldavHost': c.caldavHost,
        'caldavPort': c.caldavPort,
        'caldavPrincipalPath': c.caldavPrincipalPath,
        'scopes': c.scopes,
        'extra': c.extra,
      });

  static AccountConfig _decodeConfig(String s) {
    final m = jsonDecode(s) as Map<String, dynamic>;
    return AccountConfig(
      ewsUrl: m['ewsUrl'] as String?,
      caldavHost: m['caldavHost'] as String?,
      caldavPort: m['caldavPort'] as int?,
      caldavPrincipalPath: m['caldavPrincipalPath'] as String?,
      scopes: (m['scopes'] as List?)?.cast<String>() ?? const [],
      extra: (m['extra'] as Map?)?.cast<String, String>() ?? const {},
    );
  }

  static String _encodeRefresh(RefreshPolicy p) =>
      jsonEncode({'mode': p.mode.index, 'min': p.interval.inMinutes});

  static RefreshPolicy _decodeRefresh(String s) {
    final m = jsonDecode(s) as Map<String, dynamic>;
    return RefreshPolicy(
      mode: RefreshMode.values[(m['mode'] as int?) ?? 1],
      interval: Duration(minutes: (m['min'] as int?) ?? 15),
    );
  }
}
