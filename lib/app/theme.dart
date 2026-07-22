import 'package:flutter/material.dart';

/// Тёмная тема в духе референса Fantastical (FR-C4).
///
/// Красный — только акцент (сегодня, линия времени, FAB). Поверхности —
/// нейтрально-серые: убираем «коричневый» тинт Material 3 от красного seed,
/// иначе диалоги/меню/выбранные сегменты получаются грязно-коричневыми.
ThemeData buildDarkTheme() {
  const seed = Color(0xFFE53935);
  final base = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
  final scheme = base.copyWith(
    surface: const Color(0xFF1C1C1E),
    surfaceTint: Colors.transparent, // ← главный фикс: без красного тинта M3
    surfaceContainerLowest: const Color(0xFF141416),
    surfaceContainerLow: const Color(0xFF1C1C1E),
    surfaceContainer: const Color(0xFF202022),
    surfaceContainerHigh: const Color(0xFF272729), // фон диалогов/поповеров
    surfaceContainerHighest: const Color(0xFF2E2E31),
    secondaryContainer: const Color(0xFF33343A), // выбранный сегмент/чип
    onSecondaryContainer: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF161618),
    fontFamily: 'Roboto',
    dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xFF202022), surfaceTintColor: Colors.transparent),
    popupMenuTheme: const PopupMenuThemeData(
        color: Color(0xFF272729), surfaceTintColor: Colors.transparent),
    bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF1C1C1E), surfaceTintColor: Colors.transparent),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: seed, foregroundColor: Colors.white),
  );
}
