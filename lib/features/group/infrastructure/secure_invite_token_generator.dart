import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../domain/group_invite.dart';

final class SecureInviteTokenGenerator implements InviteTokenGenerator {
  SecureInviteTokenGenerator({Random? random})
    : _random = random ?? Random.secure();

  static const int tokenByteLength = 16;

  final Random _random;

  @override
  GeneratedInviteToken generate() {
    final bytes = List<int>.generate(
      tokenByteLength,
      (_) => _random.nextInt(256),
      growable: false,
    );
    final rawToken = base64Url.encode(bytes).replaceAll('=', '');
    return GeneratedInviteToken(rawToken: rawToken, hash: hash(rawToken));
  }

  @override
  String hash(String rawToken) {
    return sha256.convert(utf8.encode(rawToken.trim())).toString();
  }
}
