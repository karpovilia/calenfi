// PoC: реальный Google Calendar через GoogleProvider.
// Запуск: dart run calenfi:google_probe [email] [--days N]

import 'dart:io';

import 'package:calenfi/data/providers/calendar/google/google_provider.dart';
import 'package:calenfi/data/providers/calendar/google/google_token.dart';
import 'package:calenfi/domain/models/account.dart';
import 'package:calenfi/domain/models/enums.dart';
import 'package:calenfi/data/secure/secret_store.dart';
import 'package:calenfi/domain/providers/calendar_provider.dart';

Future<void> main(List<String> args) async {
  final email = args.firstWhere((a) => a.contains('@'), orElse: () => '');
  if (email.isEmpty) {
    stderr.writeln('использование: google_probe <email> [--days N]');
    exit(2);
  }
  final di = args.indexOf('--days');
  final days = (di >= 0 && di + 1 < args.length) ? int.parse(args[di + 1]) : 10;

  await SecretStore.instance.warmUp();
  final token = GoogleToken.loadFor(email);
  if (token == null) {
    stderr.writeln('нет calendar-токена для $email в keyring '
        '(сначала: tools/google_calendar_auth.py $email)');
    exit(1);
  }
  final account = Account(
      id: 'acc-google', provider: ProviderType.google,
      displayName: 'Google', email: email);
  final p = GoogleProvider(account: account, token: token);

  final auth = await p.authenticate(account.config);
  stdout.writeln('auth: ${auth.success ? "OK" : auth.error}');

  final cals = await p.listCalendars(account);
  stdout.writeln('календарей: ${cals.length}');
  for (final c in cals.take(12)) {
    stdout.writeln('  • ${c.name}${c.isPrimary ? " (primary)" : ""}');
  }

  final primary = cals.firstWhere((c) => c.isPrimary, orElse: () => cals.first);
  final now = DateTime.now().toUtc();
  final events = await p.fetchEvents(
      account, primary, DateRange(now, now.add(Duration(days: days))));
  events.sort((a, b) => a.startUtc.compareTo(b.startUtc));
  stdout.writeln('\nсобытия из «${primary.name}» за $days дней: ${events.length}');
  for (final e in events) {
    final conf = e.conference != null ? '  📹${e.conference!.type.name}' : '';
    stdout.writeln('  ${e.startUtc.toLocal()}  ${e.title}  [${e.myResponse.name}]$conf');
  }
  exit(0);
}
