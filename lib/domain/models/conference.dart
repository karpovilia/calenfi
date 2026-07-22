import 'enums.dart';

/// Видеоконференция, привязанная к событию (FR-M1, FR-M3/M4).
class Conference {
  const Conference({
    required this.type,
    required this.joinUrl,
    this.meetingId,
    this.password,
  });

  /// «Ожидающая» конференция: тип выбран, но реальная встреча ещё не заведена.
  /// Провижинер (при пуше Outbox) либо заведёт её нужной УЗ и подставит
  /// реальный [joinUrl], либо (тот же аккаунт умеет нативно) оставит пустым —
  /// тогда встречу создаст сам провайдер календаря (Teams↔O365, Meet↔Google).
  const Conference.pending(this.type)
      : joinUrl = '',
        meetingId = null,
        password = null;

  final ConferenceType type;
  final String joinUrl;
  final String? meetingId;
  final String? password;

  /// Реальная (уже заведённая) конференция — есть ссылка. Пустой [joinUrl]
  /// означает «ожидает провижининга / нативная».
  bool get isReady => joinUrl.isNotEmpty;
}

/// Человекочитаемое имя типа конференции (для встраивания ссылки в тело).
String conferenceLabel(ConferenceType t) => switch (t) {
      ConferenceType.meet => 'Google Meet',
      ConferenceType.teams => 'Teams',
      ConferenceType.zoom => 'Zoom',
      ConferenceType.telemost => 'Telemost',
      ConferenceType.unknown => 'Видеовстреча',
    };

/// Тело события (DESCRIPTION/Body) с встроенной ссылкой на внешне заведённую
/// конференцию — чтобы ссылка была видна в других клиентах и переразбиралась
/// парсером на обратном синке. Для нативной/отсутствующей конференции
/// возвращает [description] без изменений.
String? descriptionWithConference(String? description, Conference? conf) {
  if (conf == null || !conf.isReady) return description;
  final line = 'Подключиться (${conferenceLabel(conf.type)}): ${conf.joinUrl}';
  return (description == null || description.isEmpty)
      ? line
      : '$line\n\n$description';
}
