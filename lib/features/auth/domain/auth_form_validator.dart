enum AuthFieldError {
  required,
  invalidEmail,
  passwordTooShort,
  passwordTooLong,
}

final class AuthFormValidator {
  const AuthFormValidator._();

  static const int minimumPasswordLength = 8;
  static const int maximumPasswordLength = 128;

  static AuthFieldError? email(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return AuthFieldError.required;
    }

    final atIndex = normalized.indexOf('@');
    if (atIndex <= 0 ||
        atIndex != normalized.lastIndexOf('@') ||
        atIndex == normalized.length - 1 ||
        !normalized.substring(atIndex + 1).contains('.')) {
      return AuthFieldError.invalidEmail;
    }

    return null;
  }

  static AuthFieldError? password(String value) {
    if (value.isEmpty) {
      return AuthFieldError.required;
    }
    if (value.length < minimumPasswordLength) {
      return AuthFieldError.passwordTooShort;
    }
    if (value.length > maximumPasswordLength) {
      return AuthFieldError.passwordTooLong;
    }
    return null;
  }
}
