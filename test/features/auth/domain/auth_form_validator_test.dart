import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/auth/domain/auth_form_validator.dart';

void main() {
  group('AuthFormValidator.email', () {
    test('accepts a trimmed email address', () {
      expect(AuthFormValidator.email('  user@example.test  '), isNull);
    });

    test('rejects blank and malformed email addresses', () {
      expect(AuthFormValidator.email(''), AuthFieldError.required);
      expect(
        AuthFormValidator.email('not-an-email'),
        AuthFieldError.invalidEmail,
      );
      expect(
        AuthFormValidator.email('user@example'),
        AuthFieldError.invalidEmail,
      );
    });
  });

  group('AuthFormValidator.password', () {
    test('enforces the Phase 1 password length boundary', () {
      expect(AuthFormValidator.password(''), AuthFieldError.required);
      expect(
        AuthFormValidator.password('short'),
        AuthFieldError.passwordTooShort,
      );
      expect(
        AuthFormValidator.password(
          'a' * AuthFormValidator.minimumPasswordLength,
        ),
        isNull,
      );
      expect(
        AuthFormValidator.password(
          'a' * (AuthFormValidator.maximumPasswordLength + 1),
        ),
        AuthFieldError.passwordTooLong,
      );
    });
  });
}
