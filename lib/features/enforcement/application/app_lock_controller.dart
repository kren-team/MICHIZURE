import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/app_lock.dart';

final appLockControllerProvider =
    AsyncNotifierProvider<AppLockController, AppLockState>(
      AppLockController.new,
    );

final class AppLockController extends AsyncNotifier<AppLockState> {
  bool _reconcileInFlight = false;

  @override
  Future<AppLockState> build() {
    return ref.read(appLockRepositoryProvider).getState();
  }

  Future<bool> reconcile() async {
    if (_reconcileInFlight) {
      return false;
    }
    _reconcileInFlight = true;
    state = const AsyncLoading();
    try {
      final result = await ref.read(appLockRepositoryProvider).reconcile();
      if (ref.mounted) {
        state = AsyncData(result);
      }
      return true;
    } on Object catch (error, stackTrace) {
      if (ref.mounted) {
        state = AsyncError(error, stackTrace);
      }
      return false;
    } finally {
      _reconcileInFlight = false;
    }
  }

  Future<bool> release({
    required String debtId,
    required LockRemoteStatus resolution,
  }) async {
    if (_reconcileInFlight) {
      return false;
    }
    _reconcileInFlight = true;
    try {
      final result = await ref
          .read(appLockRepositoryProvider)
          .releaseObligation(debtId: debtId, resolution: resolution);
      if (ref.mounted) {
        state = AsyncData(result);
      }
      return true;
    } on Object catch (error, stackTrace) {
      if (ref.mounted) {
        state = AsyncError(error, stackTrace);
      }
      return false;
    } finally {
      _reconcileInFlight = false;
    }
  }
}
