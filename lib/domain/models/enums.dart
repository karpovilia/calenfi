/// Перечисления доменной модели Calenfi.
///
/// Держим их в одном файле, чтобы и провайдеры, и БД, и UI ссылались на
/// единые типы (см. docs/architecture.md §5).
library;

/// Тип календарного провайдера (адаптера).
enum ProviderType {
  google,
  graph, // Office 365 / Outlook + Teams
  caldav, // Yandex и любой CalDAV
  ews, // self-hosted Exchange
}

/// Состояние подключения/синхронизации учётной записи (FR-A6).
enum AccountStatus {
  ok,
  authError,
  needsReconnect,
  syncError, // не удалось получить данные (после 3 попыток)
  offline, // нет сети — данные не обновлялись
}

/// Статус самого события в источнике (FR-V12).
enum EventStatus {
  confirmed,
  tentative,
  cancelled,
}

/// Мой ответ на приглашение / статус участия (FR-R1, FR-V9).
///
/// [needsAction] — «направлено мне, ожидает ответа» → рисуется пунктиром.
/// [accepted] — заливка.
enum ResponseStatus {
  needsAction,
  accepted,
  declined,
  tentative,
  organizer,
}

/// Показывать занятость как (FR-E2).
enum ShowAs { busy, free }

/// Видимость события (FR-E2).
enum EventVisibility { defaultVis, private, public }

/// Тип видеоконференции (FR-M1).
enum ConferenceType { meet, teams, zoom, telemost, unknown }

/// Область действия операции над повторяющимся событием (FR-E7).
enum RecurrenceScope { thisOnly, thisAndFollowing, all }

/// Режим обновления учётной записи (FR-A10).
///
/// В local-first настоящего push нет (нужен webhook-сервер) — [frequent]
/// означает частый опрос, а не серверный push. См. docs/architecture.md §1.
enum RefreshMode { frequent, interval, manual }
