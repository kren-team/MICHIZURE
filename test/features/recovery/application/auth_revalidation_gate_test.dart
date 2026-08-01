import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/recovery/application/auth_revalidation_gate.dart';

void main() {
  test(
    'duplicate authentication rejection signals share one validation',
    () async {
      final blocker = Completer<void>();
      var calls = 0;
      final gate = AuthRevalidationGate(() async {
        calls += 1;
        await blocker.future;
      });

      final first = gate.request();
      final second = gate.request();
      await Future<void>.delayed(Duration.zero);

      expect(calls, 1);
      blocker.complete();
      await Future.wait([first, second]);
    },
  );
}
