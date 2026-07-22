/// Возможности конкретного адаптера (docs/architecture.md §6).
///
/// UI и use cases включают фичи по этим флагам, а НЕ по типу провайдера —
/// так MVP-ограничения из матрицы ФТ §6 (RSVP в CalDAV/EWS позже и т.п.)
/// выражаются данными, а не ветвлениями `if (provider == ...)`.
class ProviderCapabilities {
  const ProviderCapabilities({
    required this.crud,
    required this.incrementalSync,
    required this.rsvp,
    required this.createNativeConference,
    required this.serverReminders,
    required this.attendees,
  });

  final bool crud;
  final bool incrementalSync;
  final bool rsvp;
  final bool createNativeConference;
  final bool serverReminders;
  final bool attendees;

  static const google = ProviderCapabilities(
    crud: true,
    incrementalSync: true,
    rsvp: true,
    createNativeConference: true, // Google Meet
    serverReminders: true,
    attendees: true,
  );

  static const graph = ProviderCapabilities(
    crud: true,
    incrementalSync: true,
    rsvp: true,
    createNativeConference: true, // Teams
    serverReminders: true,
    attendees: true,
  );

  static const caldav = ProviderCapabilities(
    crud: true,
    incrementalSync: true,
    rsvp: false, // FR-R4 — позже
    createNativeConference: false,
    serverReminders: true, // VALARM
    attendees: false, // FR-E9 — позже
  );

  static const ews = ProviderCapabilities(
    crud: true,
    incrementalSync: true,
    rsvp: false, // FR-R4 — позже
    createNativeConference: false,
    serverReminders: true,
    attendees: true,
  );
}
