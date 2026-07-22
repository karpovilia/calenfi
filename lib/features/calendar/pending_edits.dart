import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repositories/event_repository.dart';
import '../../domain/models/calendar_event.dart';
import '../../sync/sync_engine.dart';

/// Одно ожидающее изменение события: до какого момента идёт обратный отсчёт,
/// какая это операция и каким было исходное состояние (для отмены).
class PendingEdit {
  const PendingEdit(
      {required this.deadline, required this.op, this.original});
  final DateTime deadline;

  /// Операция для Outbox: `'create'` (новое) или `'update'` (перенос/правка).
  final String op;

  /// Событие ДО правки (== состояние в облаке). Для `'create'` — null: отмена
  /// создания просто удаляет локальную строку (в облаке его ещё нет).
  final CalendarEvent? original;
}

/// Отложенная отправка изменений событий (перенос/ресайз) на сервер.
///
/// Изменение сразу видно локально ([EventRepository.putLocalDirty] — событие
/// становится dirty и не затирается синком), но в облако (Outbox + sync) уходит
/// только по истечении задержки или по «применить сейчас». Таймер сбрасывается
/// при каждом новом изменении того же события. Задержка `0` → отправляем сразу,
/// без ожидающего состояния (как раньше).
class PendingEditsNotifier extends StateNotifier<Map<String, PendingEdit>> {
  PendingEditsNotifier(this._events, this._sync) : super(const {});

  final EventRepository _events;
  final SyncEngine _sync;
  final Map<String, Timer> _timers = {};

  /// Применить изменение [updated] с задержкой [delay]. Локально пишем сразу;
  /// на сервер — по таймеру/галочке (или мгновенно, если delay == 0). [original]
  /// — состояние ДО правки, сохраняется для отмены (вернуть из облака). Первое
  /// ожидающее изменение фиксирует original; повторные правки того же события
  /// его не перезаписывают (отмена всегда возвращает к исходному облачному).
  Future<void> stage(CalendarEvent updated, Duration delay,
      {String op = 'update', CalendarEvent? original}) async {
    await _events.putLocalDirty(updated); // локально видно правку сразу
    _timers.remove(updated.id)?.cancel(); // сброс таймера при новом изменении
    // Повторная правка того же события: сохраняем исходную операцию (create
    // остаётся create) и первое original (отмена всегда → к облачному).
    final prev = state[updated.id];
    final keepOp = prev?.op ?? op;
    final base = prev?.original ?? original;
    if (delay <= Duration.zero) {
      _clear(updated.id);
      await _commit(updated.id, keepOp); // сразу на сервер, без ожидающего UI
      return;
    }
    _timers[updated.id] = Timer(delay, () => _commit(updated.id, keepOp));
    state = {
      ...state,
      updated.id: PendingEdit(
          deadline: DateTime.now().add(delay), op: keepOp, original: base),
    };
  }

  /// «Применить сейчас» — досрочно отправить на сервер.
  Future<void> applyNow(String id) async {
    final op = state[id]?.op ?? 'update';
    _timers.remove(id)?.cancel();
    await _commit(id, op);
  }

  /// Отменить ожидающее изменение: для `update` — вернуть исходное (облачное)
  /// состояние; для `create` — удалить локальную строку (в облаке его нет).
  Future<void> cancel(String id) async {
    final pend = state[id];
    _clear(id);
    if (pend == null) return;
    if (pend.op == 'create') {
      await _events.hardDelete(id);
    } else if (pend.original != null) {
      await _events.putLocalClean(pend.original!);
    }
  }

  /// Отправить сейчас ВСЕ ожидающие изменения (кнопка «в облако» сверху).
  Future<void> applyAll() async {
    for (final id in state.keys.toList()) {
      await applyNow(id);
    }
  }

  /// Отменить ВСЕ ожидающие изменения (вернуть всё из облака).
  Future<void> cancelAll() async {
    for (final id in state.keys.toList()) {
      await cancel(id);
    }
  }

  Future<void> _commit(String id, String op) async {
    _clear(id);
    await _events.enqueue(op, id);
    final e = await _events.getById(id);
    if (e != null) {
      final accId = e.source.accountId.isNotEmpty
          ? e.source.accountId
          : e.calendarId.split('|').first; // для только что созданного
      if (accId.isNotEmpty) await _sync.syncAccountById(accId);
    }
  }

  void _clear(String id) {
    _timers.remove(id)?.cancel();
    if (state.containsKey(id)) {
      final m = {...state}..remove(id);
      state = m;
    }
  }

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}

final pendingEditsProvider =
    StateNotifierProvider<PendingEditsNotifier, Map<String, PendingEdit>>((ref) {
  return PendingEditsNotifier(
    ref.watch(eventRepositoryProvider),
    ref.watch(syncEngineProvider),
  );
});
