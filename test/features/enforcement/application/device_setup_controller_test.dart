import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/enforcement/domain/device_capabilities.dart';
import 'package:michizure/features/enforcement/application/device_setup_controller.dart';
import 'package:michizure/features/enforcement/domain/enforcement_failure.dart';

import '../support/fake_device_control_repository.dart';

void main() {
  test(
    'loads capabilities, catalog, and only valid persisted selections',
    () async {
      final repository = FakeDeviceControlRepository()
        ..selectedPackageNames = {
          'social.app',
          'com.kren.michizure',
          'removed.app',
        };
      final container = _container(repository);

      final state = await container.read(deviceSetupControllerProvider.future);

      expect(state.capabilities.isManagedDemoReady, isTrue);
      expect(state.apps, hasLength(3));
      expect(state.selectedPackageNames, {'social.app'});
      expect(state.savedApps.map((app) => app.label), ['Social']);
    },
  );

  test('selects and unselects only eligible apps', () async {
    final repository = FakeDeviceControlRepository();
    final container = _container(repository);
    await container.read(deviceSetupControllerProvider.future);
    final controller = container.read(deviceSetupControllerProvider.notifier);

    controller.togglePackage('social.app', selected: true);
    controller.togglePackage('com.kren.michizure', selected: true);
    expect(
      container
          .read(deviceSetupControllerProvider)
          .requireValue
          .selectedPackageNames,
      {'social.app'},
    );

    controller.togglePackage('social.app', selected: false);
    expect(
      container
          .read(deviceSetupControllerProvider)
          .requireValue
          .selectedPackageNames,
      isEmpty,
    );
  });

  test('scoped launcher visibility does not block managed demo readiness', () {
    const capabilities = DeviceCapabilities(
      isDeviceOwner: true,
      hasUsageAccess: true,
      hasNotificationPermission: true,
      packageVisibility: PackageVisibility.scoped,
      isUserUnlocked: true,
      supportsHardEnforcement: true,
      sdkInt: 36,
    );

    expect(capabilities.isManagedDemoReady, isTrue);
  });

  test('save is single-flight and restores persisted selection', () async {
    final repository = FakeDeviceControlRepository()
      ..saveCompleter = Completer<Set<String>>();
    final container = _container(repository);
    await container.read(deviceSetupControllerProvider.future);
    final controller = container.read(deviceSetupControllerProvider.notifier)
      ..togglePackage('video.app', selected: true);

    final first = controller.save();
    final second = controller.save();

    expect(repository.saveCalls, 1);
    repository.saveCompleter!.complete({'video.app'});
    expect(await first, isTrue);
    expect(await second, isFalse);
    expect(
      container
          .read(deviceSetupControllerProvider)
          .requireValue
          .savedPackageNames,
      {'video.app'},
    );

    container.invalidate(deviceSetupControllerProvider);
    final restored = await container.read(deviceSetupControllerProvider.future);
    expect(restored.selectedPackageNames, {'video.app'});
  });

  test('keeps selection and exposes typed failure when save fails', () async {
    final repository = FakeDeviceControlRepository()
      ..saveError = const EnforcementFailure(
        EnforcementFailureKind.nativeStateCorrupt,
      );
    final container = _container(repository);
    await container.read(deviceSetupControllerProvider.future);
    final controller = container.read(deviceSetupControllerProvider.notifier)
      ..togglePackage('social.app', selected: true);

    expect(await controller.save(), isFalse);

    final state = container.read(deviceSetupControllerProvider).requireValue;
    expect(state.selectedPackageNames, {'social.app'});
    expect(
      state.commandFailure?.kind,
      EnforcementFailureKind.nativeStateCorrupt,
    );
  });
}

ProviderContainer _container(FakeDeviceControlRepository repository) {
  final container = ProviderContainer(
    overrides: [deviceControlRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
}
