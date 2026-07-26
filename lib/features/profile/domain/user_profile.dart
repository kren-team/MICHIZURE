import 'package:flutter/foundation.dart';

@immutable
final class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    required this.photoUrl,
    required this.groupId,
    required this.activeTaskSessionId,
    required this.createdAt,
    required this.updatedAt,
  });

  static const int schemaVersion = 1;

  final String id;
  final String displayName;
  final String? photoUrl;
  final String? groupId;
  final String? activeTaskSessionId;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class ProfileValidator {
  const ProfileValidator._();

  static const int maximumDisplayNameLength = 40;
  static final RegExp _disallowedCharacters = RegExp(
    '[\\x00-\\x1F\\x7F-\\x9F\\u2028\\u2029]',
  );

  static String normalizeDisplayName(String value) => value.trim();

  static int unicodeScalarLength(String value) => value.runes.length;

  static bool isValidDisplayName(String value) {
    final normalized = normalizeDisplayName(value);
    return normalized.isNotEmpty &&
        unicodeScalarLength(normalized) <= maximumDisplayNameLength &&
        !_disallowedCharacters.hasMatch(normalized);
  }
}
