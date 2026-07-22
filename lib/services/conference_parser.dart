import '../domain/models/conference.dart';
import '../domain/models/enums.dart';

/// Распознавание видеоссылок в событии (FR-M1).
///
/// Сканирует произвольный текст (location + description + conferenceData) и
/// определяет тип конференции и join-url для кнопки «Присоединиться» (FR-M2).
class ConferenceParser {
  const ConferenceParser();

  /// Удобный вход: склеивает поля события и парсит.
  Conference? detect({String? location, String? description, String? rawUrl}) {
    final text = [rawUrl, location, description]
        .where((s) => s != null && s.isNotEmpty)
        .join('\n');
    return parse(text);
  }

  /// Возвращает первую распознанную конференцию или null.
  Conference? parse(String text) {
    for (final m in _matchers) {
      final match = m.pattern.firstMatch(text);
      if (match != null) {
        return Conference(
          type: m.type,
          joinUrl: _cleanUrl(match.group(0)!),
          meetingId: m.idGroup != null ? match.group(m.idGroup!) : null,
          password: _extractPwd(text),
        );
      }
    }
    return null;
  }

  static String? _extractPwd(String text) {
    final m = RegExp(r'[?&]pwd=([^\s&"<>]+)').firstMatch(text);
    return m?.group(1);
  }

  /// Срезает хвостовую пунктуацию/скобки, прилипшие к ссылке из текста описания
  /// (напр. `…/j/123>` или `(…/j/123)` → битый join).
  static String _cleanUrl(String url) {
    var u = url;
    while (u.isNotEmpty && '>)].,;:"\'<'.contains(u[u.length - 1])) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  // Порядок важен: более специфичные раньше.
  //
  // В классах символов исключаем `"<>` (помимо пробелов): в HTML-теле события
  // (Graph/EWS отдают description как HTML) ссылка обёрнута в `<a href="URL">…`,
  // и без этого URL «съедал» хвост `">…` из тега → битый join.
  static final List<_Matcher> _matchers = [
    _Matcher(
      ConferenceType.zoom,
      RegExp(r'https?://[\w.-]*zoom\.us/j/(\d+)[^\s"<>]*', caseSensitive: false),
      idGroup: 1,
    ),
    _Matcher(
      ConferenceType.teams,
      RegExp(
          r'https?://teams\.(?:microsoft|live)\.com/l/meetup-join/[^\s"<>]+|https?://teams\.live\.com/meet/[^\s"<>]+',
          caseSensitive: false),
    ),
    _Matcher(
      ConferenceType.meet,
      RegExp(r'https?://meet\.google\.com/([a-z]{3}-[a-z]{4}-[a-z]{3})',
          caseSensitive: false),
      idGroup: 1,
    ),
    _Matcher(
      ConferenceType.telemost,
      RegExp(r'https?://telemost\.(?:360\.)?yandex\.ru/[^\s"<>]+',
          caseSensitive: false),
    ),
    // Прочие сервисы видеосвязи (КТalk, СберJazz, Dion, TrueConf, VideoMost,
    // Webinar, Pruffme, МТС Link, Контур.Толк и т.п.). Распознаём как встречу,
    // чтобы ссылка не трактовалась как адрес и не открывалась в картах.
    _Matcher(
      ConferenceType.unknown,
      RegExp(
          r'https?://[\w.-]*(?:ktalk\.ru|talk\.contour\.ru|jazz\.sber\.ru|salutejazz\.ru|dion\.vc|trueconf\.[\w.]+|videomost\.com|webinar\.ru|pruffme\.com|mts-link\.ru|vinteo\.com|contact\.mail\.ru|meet\.[\w.-]+)/[^\s"<>]+',
          caseSensitive: false),
    ),
  ];
}

class _Matcher {
  _Matcher(this.type, this.pattern, {this.idGroup});
  final ConferenceType type;
  final RegExp pattern;
  final int? idGroup;
}
