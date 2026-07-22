import 'package:calenfi/domain/models/attendee.dart';
import 'package:calenfi/domain/models/calendar_event.dart';
import 'package:calenfi/domain/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

/// Переговорка — отдельная категория поверх участников: `room` = ресурс-комната,
/// `people` = только люди. Сосуществует с видеовстречей.
void main() {
  CalendarEvent ev(List<Attendee> attendees) => CalendarEvent(
        id: 'e1',
        calendarId: 'c1',
        title: 'Встреча',
        startUtc: DateTime.utc(2026, 7, 10, 12),
        endUtc: DateTime.utc(2026, 7, 10, 13),
        timeZoneId: 'UTC',
        allDay: false,
        attendees: attendees,
        myResponse: ResponseStatus.organizer,
        showAs: ShowAs.busy,
        visibility: EventVisibility.defaultVis,
        reminders: const [],
        source: const EventSource(accountId: 'a1', calendarId: 'c1'),
      );

  test('room возвращает ресурс, people исключает его', () {
    final e = ev([
      const Attendee(email: 'ivan@x.ru'),
      const Attendee(email: 'room-501@x.ru', isResource: true),
      const Attendee(email: 'olga@x.ru'),
    ]);
    expect(e.room?.email, 'room-501@x.ru');
    expect(e.people.map((a) => a.email), ['ivan@x.ru', 'olga@x.ru']);
  });

  test('нет ресурса → room == null, people == все', () {
    final e = ev([const Attendee(email: 'ivan@x.ru')]);
    expect(e.room, isNull);
    expect(e.people.length, 1);
  });

  test('пустой список участников', () {
    final e = ev(const []);
    expect(e.room, isNull);
    expect(e.people, isEmpty);
  });
}
