import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/profile/domain/user_profile.dart';

void main() {
  group('ProfileValidator', () {
    test('normalizes surrounding whitespace', () {
      expect(ProfileValidator.normalizeDisplayName('  Alice  '), 'Alice');
    });

    test('accepts Unicode display names up to 40 scalar values', () {
      for (final name in [
        '野々村 奏',
        '奏',
        'かなで',
        'カナデ',
        'Kanade',
        'Kanade 野々村',
        'user123',
        '奏' * 40,
      ]) {
        expect(ProfileValidator.isValidDisplayName(name), isTrue);
      }
    });

    test('rejects blank, control characters, and too-long names', () {
      for (final name in ['', '  ', '\n', 'Kanade\n奏', '奏' * 41]) {
        expect(ProfileValidator.isValidDisplayName(name), isFalse);
      }
    });

    test('counts Unicode scalar values instead of UTF-16 code units', () {
      expect(ProfileValidator.unicodeScalarLength('奏😀'), 2);
    });
  });
}
