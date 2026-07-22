import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/models/account.dart';
import '../../domain/models/enums.dart';

/// Жирная плашка сверху, если какой-то отображаемый аккаунт **отвалился**
/// (после 3 попыток синка) или **нет сети** — критично, чтобы пользователь
/// не принял устаревшие/пустые данные за актуальные.
class AccountHealthBanner extends ConsumerWidget {
  const AccountHealthBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    final accounts = accountsAsync.value ?? const <Account>[];
    final unhealthy = accounts.where((a) => !a.isHealthy).toList();
    if (unhealthy.isEmpty) return const SizedBox.shrink();

    final offline = unhealthy.any((a) => a.status == AccountStatus.offline);
    final color = offline ? const Color(0xFFB26A00) : const Color(0xFFB00020);

    return Material(
      color: color,
      child: InkWell(
        onTap: () => ref.read(syncTriggerProvider)(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 3, 6, 3),
          child: Row(
            children: [
              Icon(offline ? Icons.cloud_off : Icons.error_outline,
                  color: Colors.white, size: 15),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Не обновилось: ${unhealthy.map(_line).join(', ')}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              InkWell(
                onTap: () => ref.read(syncTriggerProvider)(),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  child: Text('Повторить',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Короткая метка: «Имя (причина)» — без времени, чтобы плашка была узкой.
  String _line(Account a) {
    final what = switch (a.status) {
      AccountStatus.offline => 'нет сети',
      AccountStatus.authError => 'ошибка авторизации',
      AccountStatus.needsReconnect => 'переподключение',
      _ => 'сбой',
    };
    return '${a.displayName} ($what)';
  }
}
