import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/enforcement/domain/device_capabilities.dart';
import 'package:michizure/features/enforcement/domain/enforcement_failure.dart';
import 'package:michizure/features/enforcement/domain/lockable_app.dart';
import 'package:michizure/features/enforcement/infrastructure/device_control_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/device_control/v1');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps the versioned native capability and app-list contract', () async {
    final calls = <MethodCall>[];
    _handle(channel, (call) {
      calls.add(call);
      return switch (call.method) {
        'getCapabilities' => _capabilitiesPayload,
        'listLockableApps' => {
          'contractVersion': 1,
          'apps': [
            {
              'packageName': 'social.app',
              'label': 'Social',
              'isSelectable': true,
              'protectionReason': null,
            },
            {
              'packageName': 'launcher.app',
              'label': 'Launcher',
              'isSelectable': false,
              'protectionReason': 'launcher',
            },
          ],
        },
        _ => throw MissingPluginException(),
      };
    });
    final repository = MethodChannelDeviceControlRepository(channel: channel);

    final capabilities = await repository.getCapabilities();
    final apps = await repository.listLockableApps();

    expect(capabilities.packageVisibility, PackageVisibility.broad);
    expect(capabilities.isManagedDemoReady, isTrue);
    expect(apps.first.packageName, 'social.app');
    expect(apps.last.protectionReason, PackageProtectionReason.launcher);
    expect(
      calls.every(
        (call) =>
            (call.arguments as Map<Object?, Object?>)['contractVersion'] == 1,
      ),
      isTrue,
    );
  });

  test(
    'saves and restores selected packages with stable method names',
    () async {
      final calls = <MethodCall>[];
      _handle(channel, (call) {
        calls.add(call);
        return {
          'contractVersion': 1,
          'packageNames': ['social.app', 'video.app'],
        };
      });
      final repository = MethodChannelDeviceControlRepository(channel: channel);

      expect(await repository.getSelectedPackageNames(), {
        'social.app',
        'video.app',
      });
      expect(
        await repository.saveSelectedPackageNames({'video.app', 'social.app'}),
        {'social.app', 'video.app'},
      );

      expect(calls.map((call) => call.method), [
        'getSelectedPackages',
        'saveSelectedPackages',
      ]);
      final saveArguments = calls.last.arguments as Map<Object?, Object?>;
      expect(saveArguments['contractVersion'], 1);
      expect(saveArguments['packageNames'], ['social.app', 'video.app']);
    },
  );

  test('rejects mismatched versions and malformed app payloads', () async {
    _handle(channel, (_) => {'contractVersion': 2});
    final repository = MethodChannelDeviceControlRepository(channel: channel);

    await expectLater(
      repository.getCapabilities(),
      throwsA(
        isA<EnforcementFailure>().having(
          (failure) => failure.kind,
          'kind',
          EnforcementFailureKind.channelContractMismatch,
        ),
      ),
    );

    _handle(
      channel,
      (_) => {
        'contractVersion': 1,
        'apps': [
          {
            'packageName': 'bad.app',
            'label': 'Bad',
            'isSelectable': true,
            'protectionReason': 'launcher',
          },
        ],
      },
    );
    await expectLater(
      repository.listLockableApps(),
      throwsA(
        isA<EnforcementFailure>().having(
          (failure) => failure.kind,
          'kind',
          EnforcementFailureKind.invalidData,
        ),
      ),
    );
  });

  test('converts PlatformException and timeout to typed failures', () async {
    _handle(
      channel,
      (_) => throw PlatformException(
        code: 'packageProtected',
        message: 'native details must not escape',
      ),
    );
    final repository = MethodChannelDeviceControlRepository(channel: channel);

    await expectLater(
      repository.saveSelectedPackageNames({'settings.app'}),
      throwsA(
        isA<EnforcementFailure>().having(
          (failure) => failure.kind,
          'kind',
          EnforcementFailureKind.packageProtected,
        ),
      ),
    );

    _handle(channel, (_) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return _capabilitiesPayload;
    });
    final timedRepository = MethodChannelDeviceControlRepository(
      channel: channel,
      timeout: const Duration(milliseconds: 1),
    );
    await expectLater(
      timedRepository.getCapabilities(),
      throwsA(
        isA<EnforcementFailure>().having(
          (failure) => failure.kind,
          'kind',
          EnforcementFailureKind.timeout,
        ),
      ),
    );
  });
}

void _handle(
  MethodChannel channel,
  FutureOr<Object?> Function(MethodCall call) handler,
) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async => handler(call));
}

const _capabilitiesPayload = <String, Object?>{
  'contractVersion': 1,
  'isDeviceOwner': true,
  'hasUsageAccess': true,
  'hasNotificationPermission': true,
  'hasBroadPackageVisibility': true,
  'isUserUnlocked': true,
  'supportsHardEnforcement': true,
  'sdkInt': 36,
};
