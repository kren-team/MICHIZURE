final class Group {
  const Group({
    required this.id,
    required this.name,
    required this.ownerUid,
    required this.memberCount,
    required this.createdAt,
    required this.updatedAt,
  });

  static const int schemaVersion = 1;
  static const int maximumMemberCount = 40;

  final String id;
  final String name;
  final String ownerUid;
  final int memberCount;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class GroupNameValidator {
  const GroupNameValidator._();

  static const int maximumLength = 50;
  static final RegExp _disallowedCharacters = RegExp(
    '[\\x00-\\x1F\\x7F-\\x9F\\u2028\\u2029]',
  );

  static String normalize(String value) => value.trim();

  static bool isValid(String value) {
    final normalized = normalize(value);
    return normalized.isNotEmpty &&
        normalized.runes.length <= maximumLength &&
        !_disallowedCharacters.hasMatch(normalized);
  }
}
