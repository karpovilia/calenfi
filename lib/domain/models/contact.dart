/// Один адрес контакта.
class EmailAddress {
  const EmailAddress(this.email, {this.label, this.primary = false});

  final String email;
  final String? label; // work / home / ...
  final bool primary;

  /// Доменная часть адреса (после @), в нижнем регистре.
  String get domain {
    final i = email.lastIndexOf('@');
    return i < 0 ? '' : email.substring(i + 1).toLowerCase();
  }
}

/// Контакт (FR-K). Мастер — Google Contacts (People API), но контакт может
/// объединять несколько адресов одного человека (FR-K5).
class Contact {
  const Contact({
    required this.id,
    required this.displayName,
    this.emails = const [],
    this.defaultEmail,
    this.photoUrl,
    this.sourceAccountIds = const {},
  });

  final String id;
  final String displayName;
  final List<EmailAddress> emails;

  /// Явно заданный дефолтный адрес (FR-K7). Если null — действует правило FR-K8.
  final String? defaultEmail;

  final String? photoUrl;
  final Set<String> sourceAccountIds;
}
