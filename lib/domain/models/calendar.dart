/// Календарь внутри учётной записи (FR-A8).
class Calendar {
  const Calendar({
    required this.id,
    required this.accountId,
    required this.name,
    required this.color,
    this.nameOverride,
    this.colorOverride,
    this.defaultReminderMinutes,
    this.visible = true,
    this.syncState,
    this.isPrimary = false,
    this.readOnly = false,
  });

  /// Провайдерный id календаря.
  final String id;
  final String accountId;

  /// Имя из источника (перезаписывается синком).
  final String name;

  /// Пользовательское имя (переименование). null → используется [name].
  final String? nameOverride;

  /// Имя для отображения: пользовательское либо из источника.
  String get effectiveName => (nameOverride != null && nameOverride!.isNotEmpty)
      ? nameOverride!
      : name;

  /// ARGB-цвет из источника (перезаписывается синком).
  final int color;

  /// Пользовательский цвет (FR-A9). null → используется [color].
  final int? colorOverride;

  /// Цвет для отображения: пользовательский override либо цвет источника.
  int get effectiveColor => colorOverride ?? color;

  /// Дефолтное напоминание (минут до начала; 0 = в момент начала; null = нет).
  final int? defaultReminderMinutes;

  /// Тумблер видимости в сетке (FR-A8).
  final bool visible;

  /// Состояние инкрементального синка: syncToken / CTag / EWS syncState (FR-S2).
  final String? syncState;

  final bool isPrimary;
  final bool readOnly;

  Calendar copyWith({
    String? name,
    String? nameOverride,
    int? color,
    int? colorOverride,
    int? defaultReminderMinutes,
    bool? visible,
    String? syncState,
    bool? isPrimary,
    bool? readOnly,
  }) =>
      Calendar(
        id: id,
        accountId: accountId,
        name: name ?? this.name,
        nameOverride: nameOverride ?? this.nameOverride,
        color: color ?? this.color,
        colorOverride: colorOverride ?? this.colorOverride,
        defaultReminderMinutes:
            defaultReminderMinutes ?? this.defaultReminderMinutes,
        visible: visible ?? this.visible,
        syncState: syncState ?? this.syncState,
        isPrimary: isPrimary ?? this.isPrimary,
        readOnly: readOnly ?? this.readOnly,
      );
}
