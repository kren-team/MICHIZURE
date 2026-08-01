import 'dart:math';

import '../application/task_event_id_generator.dart';

final class SecureTaskEventIdGenerator implements TaskEventIdGenerator {
  SecureTaskEventIdGenerator([Random? random])
    : _random = random ?? Random.secure();

  final Random _random;

  @override
  String generateManualAbortId(String taskId) {
    final randomPart = List<int>.generate(
      16,
      (_) => _random.nextInt(256),
      growable: false,
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return 'manual_${taskId}_$randomPart';
  }
}
