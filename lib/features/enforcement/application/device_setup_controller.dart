import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/device_capabilities.dart';
import '../domain/device_control_repository.dart';
import '../domain/enforcement_failure.dart';
import '../domain/lockable_app.dart';

final deviceSetupControllerProvider =
    AsyncNotifierProvider<DeviceSetupController, DeviceSetupState>(
      DeviceSetupController.new,
    );

final class DeviceSetupState {
  const DeviceSetupState({
    required this.capabilities,
    required this.apps,
    required this.selectedPackageNames,
    required this.savedPackageNames,
    this.isSaving = false,
    this.commandFailure,
  });

  final DeviceCapabilities capabilities;
  final List<LockableApp> apps;
  final Set<String> selectedPackageNames;
  final Set<String> savedPackageNames;
  final bool isSaving;
  final EnforcementFailure? commandFailure;

  bool get hasUnsavedChanges =>
      !_setEquals(selectedPackageNames, savedPackageNames);

  DeviceSetupState copyWith({
    Set<String>? selectedPackageNames,
    Set<String>? savedPackageNames,
    bool? isSaving,
    EnforcementFailure? commandFailure,
    bool clearFailure = false,
  }) {
    return DeviceSetupState(
      capabilities: capabilities,
      apps: apps,
      selectedPackageNames: selectedPackageNames ?? this.selectedPackageNames,
      savedPackageNames: savedPackageNames ?? this.savedPackageNames,
      isSaving: isSaving ?? this.isSaving,
      commandFailure: clearFailure
          ? null
          : commandFailure ?? this.commandFailure,
    );
  }
}

final class DeviceSetupController extends AsyncNotifier<DeviceSetupState> {
  bool _saveInFlight = false;

  DeviceControlRepository get _repository =>
      ref.read(deviceControlRepositoryProvider);

  @override
  Future<DeviceSetupState> build() => _load();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  void togglePackage(String packageName, {required bool selected}) {
    final current = state.value;
    if (current == null || current.isSaving) {
      return;
    }
    final app = current.apps
        .where((candidate) => candidate.packageName == packageName)
        .firstOrNull;
    if (app == null || !app.isSelectable) {
      return;
    }
    final next = current.selectedPackageNames.toSet();
    selected ? next.add(packageName) : next.remove(packageName);
    state = AsyncData(
      current.copyWith(selectedPackageNames: next, clearFailure: true),
    );
  }

  Future<bool> save() async {
    final current = state.value;
    if (_saveInFlight || current == null) {
      return false;
    }
    _saveInFlight = true;
    state = AsyncData(current.copyWith(isSaving: true, clearFailure: true));
    try {
      final saved = await _repository.saveSelectedPackageNames(
        current.selectedPackageNames,
      );
      if (ref.mounted) {
        final latest = state.value ?? current;
        state = AsyncData(
          latest.copyWith(
            selectedPackageNames: saved,
            savedPackageNames: saved,
            isSaving: false,
            clearFailure: true,
          ),
        );
      }
      return true;
    } on Object catch (error) {
      if (ref.mounted) {
        final latest = state.value ?? current;
        state = AsyncData(
          latest.copyWith(isSaving: false, commandFailure: _asFailure(error)),
        );
      }
      return false;
    } finally {
      _saveInFlight = false;
    }
  }

  Future<void> openUsageAccessSettings() =>
      _runCommand(_repository.openUsageAccessSettings);

  Future<void> openNotificationSettings() =>
      _runCommand(_repository.openNotificationSettings);

  Future<DeviceSetupState> _load() async {
    final capabilities = await _repository.getCapabilities();
    final apps = await _repository.listLockableApps();
    final persisted = await _repository.getSelectedPackageNames();
    final selectablePackages = apps
        .where((app) => app.isSelectable)
        .map((app) => app.packageName)
        .toSet();
    final selected = persisted.intersection(selectablePackages);
    return DeviceSetupState(
      capabilities: capabilities,
      apps: apps,
      selectedPackageNames: selected,
      savedPackageNames: selected,
    );
  }

  Future<void> _runCommand(Future<void> Function() command) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    try {
      await command();
      if (ref.mounted) {
        state = AsyncData(current.copyWith(clearFailure: true));
      }
    } on Object catch (error) {
      if (ref.mounted) {
        state = AsyncData(current.copyWith(commandFailure: _asFailure(error)));
      }
    }
  }
}

EnforcementFailure _asFailure(Object error) {
  return error is EnforcementFailure
      ? error
      : const EnforcementFailure(EnforcementFailureKind.unknown);
}

bool _setEquals(Set<String> left, Set<String> right) {
  return left.length == right.length && left.containsAll(right);
}
