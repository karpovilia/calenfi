import 'package:calenfi/domain/models/enums.dart';
import 'package:calenfi/services/conference_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = ConferenceParser();

  group('ConferenceParser (FR-M1)', () {
    test('распознаёт Zoom + meetingId + pwd', () {
      final c = parser.parse(
          'Join: https://us06web.zoom.us/j/84538569211?pwd=h9mxRRyE92kGX0');
      expect(c, isNotNull);
      expect(c!.type, ConferenceType.zoom);
      expect(c.meetingId, '84538569211');
      expect(c.password, 'h9mxRRyE92kGX0');
    });

    test('распознаёт Microsoft Teams', () {
      final c = parser.parse(
          'https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc/0');
      expect(c?.type, ConferenceType.teams);
    });

    test('распознаёт Google Meet + код', () {
      final c = parser.parse('Видео: https://meet.google.com/abc-defg-hij');
      expect(c?.type, ConferenceType.meet);
      expect(c?.meetingId, 'abc-defg-hij');
    });

    test('распознаёт Yandex Telemost', () {
      final c = parser.parse('https://telemost.yandex.ru/j/1234567890');
      expect(c?.type, ConferenceType.telemost);
    });

    test('возвращает null когда ссылок нет', () {
      expect(parser.parse('Обычная встреча без ссылки'), isNull);
    });

    test('detect() склеивает поля события', () {
      final c = parser.detect(
        location: 'Переговорка 3',
        description: 'Подключайтесь: https://meet.google.com/xyz-abcd-efg',
      );
      expect(c?.type, ConferenceType.meet);
    });
  });
}
