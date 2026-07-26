import 'package:flutter/foundation.dart';

@immutable
final class AuthUser {
  const AuthUser({required this.id});

  final String id;

  @override
  bool operator ==(Object other) => other is AuthUser && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
