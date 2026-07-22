/// Напоминание о событии (FR-N2).
class Reminder {
  const Reminder({required this.before, this.popup = true});

  /// За сколько до начала события.
  final Duration before;

  /// popup (локальное уведомление) vs email — в MVP используем popup.
  final bool popup;
}
