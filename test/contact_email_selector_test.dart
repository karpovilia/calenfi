import 'package:calenfi/domain/models/contact.dart';
import 'package:calenfi/services/contact_email_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sel = ContactEmailSelector();

  Contact contact({String? def, List<EmailAddress> emails = const []}) => Contact(
        id: 'c1',
        displayName: 'Иван',
        defaultEmail: def,
        emails: emails,
      );

  group('ContactEmailSelector (FR-K8)', () {
    test('1) дефолтный адрес имеет приоритет', () {
      final c = contact(def: 'ivan@default.ru', emails: [
        const EmailAddress('ivan@work.com'),
        const EmailAddress('ivan@gmail.com'),
      ]);
      expect(sel.select(c, 'me@work.com'), 'ivan@default.ru');
    });

    test('2) при отсутствии дефолта — совпадение домена с аккаунтом', () {
      final c = contact(emails: [
        const EmailAddress('ivan@personal.com'),
        const EmailAddress('ivan@company.com'),
      ]);
      expect(sel.select(c, 'me@company.com'), 'ivan@company.com');
    });

    test('3) нет совпадения домена — primary', () {
      final c = contact(emails: [
        const EmailAddress('ivan@a.com'),
        const EmailAddress('ivan@b.com', primary: true),
      ]);
      expect(sel.select(c, 'me@gmail.com'), 'ivan@b.com');
    });

    test('3) нет primary — первый адрес', () {
      final c = contact(emails: [
        const EmailAddress('ivan@a.com'),
        const EmailAddress('ivan@b.com'),
      ]);
      expect(sel.select(c, 'me@gmail.com'), 'ivan@a.com');
    });

    test('нет адресов — null', () {
      expect(sel.select(contact(), 'me@x.com'), isNull);
    });
  });
}
