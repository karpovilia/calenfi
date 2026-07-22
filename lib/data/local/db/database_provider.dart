import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database.dart';

/// Имя файла локальной БД (общее для приложения и агентского CLI).
const String kDbFileName = 'calenfi.sqlite';

/// Единственный инстанс локальной БД на всё приложение.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(_openConnection());
  ref.onDispose(db.close);
  return db;
});

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, kDbFileName));
    return NativeDatabase.createInBackground(file);
  });
}
