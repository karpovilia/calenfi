import '../domain/models/contact.dart';

/// Выбор адреса участника при добавлении в встречу (FR-K8).
///
/// Правило (буквально из требования):
///  1) если у контакта задан дефолтный адрес — использовать его;
///  2) иначе — адрес, чей домен совпадает с аккаунтом, из которого создаётся
///     событие (поле `calendar`);
///  3) иначе — primary / первый адрес контакта.
class ContactEmailSelector {
  const ContactEmailSelector();

  /// [schedulingAccountEmail] — почта аккаунта, из которого ставится встреча.
  String? select(Contact contact, String schedulingAccountEmail) {
    // 1) дефолтный адрес
    final def = contact.defaultEmail;
    if (def != null && def.isNotEmpty) return def;

    if (contact.emails.isEmpty) return null;

    // 2) совпадение домена с аккаунтом создания
    final acctDomain = _domain(schedulingAccountEmail);
    if (acctDomain.isNotEmpty) {
      for (final e in contact.emails) {
        if (e.domain == acctDomain) return e.email;
      }
    }

    // 3) primary / первый
    final primary = contact.emails.where((e) => e.primary);
    if (primary.isNotEmpty) return primary.first.email;
    return contact.emails.first.email;
  }

  static String _domain(String email) {
    final i = email.lastIndexOf('@');
    return i < 0 ? '' : email.substring(i + 1).toLowerCase();
  }
}
