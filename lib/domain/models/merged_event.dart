import 'calendar_event.dart';

/// Представление склеенного события для UI (FR-D1, FR-D3).
///
/// Дедуп — это view-level группировка: исходные [CalendarEvent] не мутируются,
/// движок лишь группирует их в [MergedEvent] (см. docs/architecture.md §10).
class MergedEvent {
  const MergedEvent({
    required this.groupId,
    required this.primary,
    required this.sources,
  });

  final String groupId;

  /// «Основной» источник — для редактирования по умолчанию (FR-D5).
  final CalendarEvent primary;

  /// Все события-дубли из разных календарей (включая primary), с их цветами и
  /// статусами участия (FR-D3/D4).
  final List<CalendarEvent> sources;

  bool get isMerged => sources.length > 1;

  /// Список календарей, в которых есть это событие.
  Iterable<String> get calendarIds => sources.map((e) => e.calendarId);
}
