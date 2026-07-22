// Регрессионный тест бага «событие пропадало из сетки» (июль 2026): Яндекс
// CalDAV кладёт одно приглашение с одним UID в НЕСКОЛЬКО коллекций (основной
// календарь + календарь переговорки). При id вида `acc:UID` копии коллапсировали
// в одну строку БД, и копия из СКРЫТОГО календаря переговорки перезаписывала
// копию из видимого — «Собеседование» исчезало при «всё синхронизировано».
// Контракт: id события календарно-скоупный → копии сосуществуют.

import 'package:calenfi/data/providers/calendar/caldav/caldav_provider.dart';
import 'package:calenfi/data/providers/calendar/caldav/ics.dart';
import 'package:calenfi/domain/models/account.dart';
import 'package:calenfi/domain/models/calendar.dart';
import 'package:calenfi/domain/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const acc = Account(
      id: 'acc-yandex',
      provider: ProviderType.caldav,
      displayName: 'Y',
      email: 'me@example.org');

  const mainCal = Calendar(
      id: 'acc-yandex|/calendars/me%40example.org/events-10922764/',
      accountId: 'acc-yandex',
      name: 'me@example.org',
      color: 0);
  const roomCal = Calendar(
      id: 'acc-yandex|/calendars/me%40example.org/events-6352832/',
      accountId: 'acc-yandex',
      name: 'Переговорка',
      color: 0);

  final vevent = VEvent(
    uid: 'interview-123@yandex.ru',
    summary: 'Собеседование',
    startUtc: DateTime.utc(2026, 7, 22, 11),
    endUtc: DateTime.utc(2026, 7, 22, 12),
    allDay: false,
  );

  test('один UID в двух календарях → РАЗНЫЕ id (копии сосуществуют)', () {
    final p = CalDavProvider(account: acc, password: 'x');
    final inMain = p.buildEventForTest(acc, mainCal, vevent);
    final inRoom = p.buildEventForTest(acc, roomCal, vevent);

    expect(inMain.id, isNot(inRoom.id),
        reason: 'коллизия id: копия из скрытого календаря затрёт видимую');
    // Токен календаря в id — последний сегмент пути коллекции.
    expect(inMain.id, 'acc-yandex:events-10922764:interview-123@yandex.ru');
    expect(inRoom.id, 'acc-yandex:events-6352832:interview-123@yandex.ru');
    // Каждая копия привязана к своему календарю (видимость фильтрует отдельно).
    expect(inMain.calendarId, mainCal.id);
    expect(inRoom.calendarId, roomCal.id);
  });

  test('дедуп склеит копии в одну карточку (одинаковые название+время)', () {
    final p = CalDavProvider(account: acc, password: 'x');
    final a = p.buildEventForTest(acc, mainCal, vevent);
    final b = p.buildEventForTest(acc, roomCal, vevent);
    // Эвристика dedup_engine: normalized title + start + end (см. FR-D2).
    expect(a.title == b.title && a.startUtc == b.startUtc && a.endUtc == b.endUtc,
        isTrue);
  });
}
