import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/group/infrastructure/secure_invite_token_generator.dart';

void main() {
  test('generates a 128-bit base64url token and SHA-256 hex hash', () {
    final generator = SecureInviteTokenGenerator(random: Random(1));

    final token = generator.generate();

    expect(token.rawToken, hasLength(22));
    expect(token.rawToken, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    expect(token.hash, hasLength(64));
    expect(token.hash, matches(RegExp(r'^[a-f0-9]+$')));
    expect(generator.hash(token.rawToken), token.hash);
    expect(token.hash, isNot(contains(token.rawToken)));
  });

  test('trims a shared token before hashing', () {
    final generator = SecureInviteTokenGenerator(random: Random(1));
    final token = generator.generate();

    expect(generator.hash('  ${token.rawToken}  '), token.hash);
  });
}
