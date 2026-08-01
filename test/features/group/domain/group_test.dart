import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/group/domain/group.dart';

void main() {
  group('GroupNameValidator', () {
    test('accepts normalized Unicode group names up to 50 scalars', () {
      for (final name in ['朝活チーム', 'Team 野々村', '仲間' * 25]) {
        expect(GroupNameValidator.isValid(name), isTrue);
      }
    });

    test('normalizes surrounding whitespace', () {
      expect(GroupNameValidator.normalize('  朝活チーム  '), '朝活チーム');
    });

    test('rejects blank, control characters, and names over 50 scalars', () {
      for (final name in ['', '  ', 'Group\nName', '仲' * 51]) {
        expect(GroupNameValidator.isValid(name), isFalse);
      }
    });
  });
}
