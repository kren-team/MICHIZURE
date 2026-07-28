import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/enforcement/domain/device_capabilities.dart';
import 'package:michizure/features/enforcement/domain/enforcement_failure.dart';
import 'package:michizure/features/enforcement/presentation/device_setup/device_setup_screen.dart';

import '../support/fake_device_control_repository.dart';

void main() {
  testWidgets('shows ready capability checklist on a managed demo device', (
    tester,
  ) async {
    await _pump(tester, FakeDeviceControlRepository());

    expect(find.text('デモ端末の準備ができています'), findsOneWidget);
    expect(find.byKey(const Key('device-owner-capability')), findsOneWidget);
    expect(find.byKey(const Key('usage-access-capability')), findsOneWidget);
    expect(
      find.byKey(const Key('package-visibility-capability')),
      findsOneWidget,
    );
  });

  testWidgets('shows actionable setup without crashing on a normal device', (
    tester,
  ) async {
    final repository = FakeDeviceControlRepository()
      ..capabilities = const DeviceCapabilities(
        isDeviceOwner: false,
        hasUsageAccess: false,
        hasNotificationPermission: false,
        packageVisibility: PackageVisibility.scoped,
        isUserUnlocked: true,
        supportsHardEnforcement: true,
        sdkInt: 36,
      );
    await _pump(tester, repository);

    expect(find.text('タスク開始前に端末の準備が必要です'), findsOneWidget);
    expect(find.text('設定を開く'), findsNWidgets(2));
    await tester.tap(find.text('設定を開く').first);
    await tester.pump();
    expect(repository.openUsageCalls, 1);
  });

  testWidgets('shows a safe typed error when the native bridge fails', (
    tester,
  ) async {
    final repository = FakeDeviceControlRepository()
      ..loadError = const EnforcementFailure(
        EnforcementFailureKind.nativeUnavailable,
      );
    await _pump(tester, repository);

    expect(find.byKey(const Key('device-setup-load-error')), findsOneWidget);
    expect(find.textContaining('PlatformException'), findsNothing);
    expect(find.textContaining('Firebase'), findsNothing);
  });
}

Future<void> _pump(
  WidgetTester tester,
  FakeDeviceControlRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceControlRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(home: DeviceSetupScreen()),
    ),
  );
  await tester.pumpAndSettle();
}
