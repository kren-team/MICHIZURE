import 'dart:math';

import '../domain/squat_detector.dart';

final class SecureSquatSessionIdGenerator implements SquatSessionIdGenerator {
  SecureSquatSessionIdGenerator({Random? random})
    : _random = random ?? Random.secure();

  final Random _random;

  @override
  String generate() {
    final bytes = List<int>.generate(18, (_) => _random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }
}
