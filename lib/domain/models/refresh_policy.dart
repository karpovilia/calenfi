import 'enums.dart';

/// Политика обновления учётной записи (FR-A10).
///
/// Переопределяет глобальный дефолт-интервал (FR-S3). В local-first [frequent]
/// — это просто короткий интервал (push недостижим без сервера).
class RefreshPolicy {
  const RefreshPolicy({
    this.mode = RefreshMode.interval,
    this.interval = const Duration(minutes: 15),
  });

  final RefreshMode mode;
  final Duration interval;

  /// Эффективный интервал опроса с учётом режима.
  Duration get effectiveInterval => switch (mode) {
        RefreshMode.frequent => const Duration(minutes: 1),
        RefreshMode.interval => interval,
        RefreshMode.manual => Duration.zero, // только ручной/при старте
      };

  RefreshPolicy copyWith({RefreshMode? mode, Duration? interval}) =>
      RefreshPolicy(mode: mode ?? this.mode, interval: interval ?? this.interval);
}
