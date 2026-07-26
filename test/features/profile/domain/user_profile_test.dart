import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/profile/domain/user_profile.dart';

void main() {
  group('ProfileValidator', () {
    test('normalizes surrounding whitespace', () {
      expect(ProfileValidator.normalizeDisplayName('  Alice  '), 'Alice');
    });

    test('accepts a non-empty name up to 40 characters', () {
      expect(ProfileValidator.isValidDisplayName('Alice'), isTrue);
      expect(ProfileValidator.isValidDisplayName('a' * 40), isTrue);
    });

    test('rejects blank and too-long names', () {
      expect(ProfileValidator.isValidDisplayName('  '), isFalse);
      expect(ProfileValidator.isValidDisplayName('a' * 41), isFalse);
    });
  });
}
