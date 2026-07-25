import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/secure/data_dir.dart';

/// Выбранный язык интерфейса. `null` — «Системный» (по локали устройства).
/// Хранится простым текстовым файлом в конфиг-каталоге (без БД — доступно до
/// её инициализации и на всех платформах). Поддерживаемые: en, ru, es, de, zh, fr.
class LocaleNotifier extends StateNotifier<Locale?> {
  LocaleNotifier() : super(_load());

  static const supported = ['en', 'ru', 'es', 'de', 'zh', 'fr'];

  static File get _file => File('${configDir()}/locale');

  static Locale? _load() {
    try {
      final f = _file;
      if (!f.existsSync()) return null;
      final code = f.readAsStringSync().trim();
      return supported.contains(code) ? Locale(code) : null;
    } on Object {
      return null;
    }
  }

  /// Задать язык (null — системный).
  Future<void> set(Locale? locale) async {
    state = locale;
    try {
      final f = _file;
      await f.parent.create(recursive: true);
      if (locale == null) {
        if (f.existsSync()) await f.delete();
      } else {
        await f.writeAsString(locale.languageCode);
      }
    } on Object {/* сохранение best-effort */}
  }
}

final localeProvider =
    StateNotifierProvider<LocaleNotifier, Locale?>((_) => LocaleNotifier());

/// Человекочитаемое имя языка (в его же локали) для переключателя.
String languageName(String code) => switch (code) {
      'en' => 'English',
      'ru' => 'Русский',
      'es' => 'Español',
      'de' => 'Deutsch',
      'zh' => '中文',
      'fr' => 'Français',
      _ => code,
    };
