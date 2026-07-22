import 'enums.dart';

/// Участник события (FR-R3).
class Attendee {
  const Attendee({
    required this.email,
    this.displayName,
    this.response = ResponseStatus.needsAction,
    this.isOrganizer = false,
    this.optional = false,
    this.isResource = false,
  });

  final String email;
  final String? displayName;
  final ResponseStatus response;
  final bool isOrganizer;
  final bool optional;

  /// Ресурс-участник: переговорная комната (room mailbox). Отдельная категория
  /// «Переговорка» — сосуществует с людьми и видеовстречей. Приглашение уходит
  /// в почту комнаты, она сама подтверждает бронь.
  final bool isResource;
}
