import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../enforcement/application/app_lock_controller.dart';
import '../../enforcement/domain/app_lock.dart';
import '../domain/debt.dart';
import '../domain/debt_failure.dart';

final debtLockReleaseControllerProvider =
    NotifierProvider<DebtLockReleaseController, DebtLockReleaseState>(
      DebtLockReleaseController.new,
    );

final debtLockReleaseStateProvider = Provider<DebtLockReleaseState>((ref) {
  return ref.watch(debtLockReleaseControllerProvider);
});

final class DebtLockReleaseState {
  const DebtLockReleaseState({
    required this.isMonitoring,
    required this.trackedDebtCount,
    this.failure,
  });

  const DebtLockReleaseState.idle()
    : isMonitoring = false,
      trackedDebtCount = 0,
      failure = null;

  final bool isMonitoring;
  final int trackedDebtCount;
  final DebtFailure? failure;
}

final class DebtLockReleaseController extends Notifier<DebtLockReleaseState> {
  StreamSubscription<DebtSnapshot<List<Debt>>>? _activeSubscription;
  final Map<String, StreamSubscription<DebtSnapshot<Debt?>>>
  _debtSubscriptions = {};
  final Set<String> _releaseInFlight = {};
  final Set<String> _releasedDebtIds = {};
  int _generation = 0;
  String? _currentUserId;

  @override
  DebtLockReleaseState build() {
    final userId = ref.watch(authStateProvider).value?.id;
    ref.onDispose(() {
      _generation += 1;
      unawaited(_cancelSubscriptions());
    });
    Future<void>.microtask(() => _restart(userId));
    return const DebtLockReleaseState.idle();
  }

  Future<void> retry() => _restart(_currentUserId);

  Future<void> _restart(String? userId) async {
    final generation = ++_generation;
    _currentUserId = userId;
    await _cancelSubscriptions();
    _releasedDebtIds.clear();
    _releaseInFlight.clear();
    if (userId == null || generation != _generation || !ref.mounted) {
      if (ref.mounted) {
        state = const DebtLockReleaseState.idle();
      }
      return;
    }

    state = const DebtLockReleaseState(isMonitoring: true, trackedDebtCount: 0);
    try {
      _activeSubscription = ref
          .read(debtRepositoryProvider)
          .watchFailedUserActiveDebts(userId)
          .listen(
            (snapshot) {
              for (final debt in snapshot.value) {
                _trackDebt(debt.id, userId, generation);
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              _publishFailure(error);
            },
          );
      final lockState = await ref.read(appLockRepositoryProvider).getState();
      if (generation != _generation) {
        return;
      }
      for (final obligation in lockState.obligations.where(
        (value) => value.isUnresolved,
      )) {
        _trackDebt(obligation.debtId, userId, generation);
      }
    } on Object catch (error) {
      _publishFailure(error, native: error is! DebtFailure);
    }
  }

  void _trackDebt(String debtId, String userId, int generation) {
    if (_debtSubscriptions.containsKey(debtId) ||
        _releasedDebtIds.contains(debtId)) {
      return;
    }
    _debtSubscriptions[debtId] = ref
        .read(debtRepositoryProvider)
        .watchDebt(debtId)
        .listen(
          (snapshot) {
            if (generation != _generation) {
              return;
            }
            final debt = snapshot.value;
            if (debt != null &&
                debt.failedUserId == userId &&
                debt.isTerminal) {
              unawaited(_release(debt));
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            _publishFailure(error);
          },
        );
    _publishTrackedCount();
  }

  Future<void> _release(Debt debt) async {
    if (_releasedDebtIds.contains(debt.id) || !_releaseInFlight.add(debt.id)) {
      return;
    }
    try {
      final resolution = switch (debt.status) {
        DebtStatus.completed => LockRemoteStatus.completed,
        DebtStatus.expired => LockRemoteStatus.expired,
        DebtStatus.active => throw const DebtFailure(
          DebtFailureKind.invalidData,
        ),
      };
      await ref
          .read(appLockRepositoryProvider)
          .releaseObligation(debtId: debt.id, resolution: resolution);
      _releasedDebtIds.add(debt.id);
      await _debtSubscriptions.remove(debt.id)?.cancel();
      ref.invalidate(appLockControllerProvider);
      _publishTrackedCount();
    } on Object catch (error) {
      _publishFailure(error, native: true);
    } finally {
      _releaseInFlight.remove(debt.id);
    }
  }

  void _publishFailure(Object error, {bool native = false}) {
    if (!ref.mounted) {
      return;
    }
    state = DebtLockReleaseState(
      isMonitoring: _currentUserId != null,
      trackedDebtCount: _debtSubscriptions.length,
      failure: error is DebtFailure
          ? error
          : DebtFailure(
              native
                  ? DebtFailureKind.nativeReleaseFailed
                  : DebtFailureKind.unknown,
            ),
    );
  }

  void _publishTrackedCount() {
    if (!ref.mounted) {
      return;
    }
    state = DebtLockReleaseState(
      isMonitoring: _currentUserId != null,
      trackedDebtCount: _debtSubscriptions.length,
    );
  }

  Future<void> _cancelSubscriptions() async {
    await _activeSubscription?.cancel();
    _activeSubscription = null;
    final subscriptions = _debtSubscriptions.values.toList(growable: false);
    _debtSubscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
}
