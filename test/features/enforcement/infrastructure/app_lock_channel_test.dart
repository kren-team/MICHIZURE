import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/enforcement/domain/app_lock.dart';
import 'package:michizure/features/enforcement/domain/enforcement_failure.dart';
import 'package:michizure/features/enforcement/infrastructure/app_lock_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/app-lock');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps a versioned lock state without package inventory', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return _payload();
        });
    final repository = MethodChannelAppLockRepository(channel: channel);

    final result = await repository.applyObligation(
      LockObligationRequest(
        debtId: 'debt-1',
        taskSessionId: 'task-1',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(2000, isUtc: true),
      ),
    );

    expect(captured?.method, 'applyLockObligation');
    expect(
      (captured?.arguments as Map<Object?, Object?>).containsKey(
        'packageNames',
      ),
      isFalse,
    );
    expect(result.hasActiveLock, isTrue);
    expect(result.obligations.single.targetCount, 2);
  });

  test('rejects unknown response fields', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {
            ..._payload(),
            'packageNames': ['private.app'],
          },
        );
    final repository = MethodChannelAppLockRepository(channel: channel);

    expect(
      repository.getState(),
      throwsA(
        isA<EnforcementFailure>().having(
          (value) => value.kind,
          'kind',
          EnforcementFailureKind.invalidData,
        ),
      ),
    );
  });

  test('maps non Device Owner to a typed failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) => throw PlatformException(code: 'notDeviceOwner'),
        );
    final repository = MethodChannelAppLockRepository(channel: channel);

    expect(
      repository.reconcile(),
      throwsA(
        isA<EnforcementFailure>().having(
          (value) => value.kind,
          'kind',
          EnforcementFailureKind.notDeviceOwner,
        ),
      ),
    );
  });
}

Map<String, Object?> _payload() {
  return {
    'contractVersion': 1,
    'obligations': [
      {
        'debtId': 'debt-1',
        'taskSessionId': 'task-1',
        'expiresAtEpochMs': 2000,
        'remoteStatus': 'active',
        'localState': 'enforced',
        'targetCount': 2,
        'enforcedCount': 2,
        'failedCount': 0,
        'errorCode': null,
      },
    ],
    'effectiveTargetCount': 2,
    'ownedSuspensionCount': 2,
    'appliedCount': 2,
    'releasedCount': 0,
    'failedCount': 0,
    'nextDeadlineEpochMs': 2000,
  };
}
