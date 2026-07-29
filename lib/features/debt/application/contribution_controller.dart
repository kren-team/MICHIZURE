import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/contribution.dart';
import 'submit_contribution.dart';

final contributionControllerProvider =
    NotifierProvider<ContributionController, ContributionControllerState>(
      ContributionController.new,
    );

final class ContributionControllerState {
  const ContributionControllerState({
    required this.isRestoring,
    required this.isSubmitting,
    required this.detectedCount,
    required this.pendingCount,
    required this.confirmedCount,
    required this.rejectedCount,
    this.lastDelivery,
  });

  const ContributionControllerState.idle()
    : isRestoring = false,
      isSubmitting = false,
      detectedCount = 0,
      pendingCount = 0,
      confirmedCount = 0,
      rejectedCount = 0,
      lastDelivery = null;

  final bool isRestoring;
  final bool isSubmitting;
  final int detectedCount;
  final int pendingCount;
  final int confirmedCount;
  final int rejectedCount;
  final ContributionDelivery? lastDelivery;

  ContributionControllerState copyWith({
    bool? isRestoring,
    bool? isSubmitting,
    int? detectedCount,
    int? pendingCount,
    int? confirmedCount,
    int? rejectedCount,
    ContributionDelivery? lastDelivery,
    bool clearLastDelivery = false,
  }) {
    return ContributionControllerState(
      isRestoring: isRestoring ?? this.isRestoring,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      detectedCount: detectedCount ?? this.detectedCount,
      pendingCount: pendingCount ?? this.pendingCount,
      confirmedCount: confirmedCount ?? this.confirmedCount,
      rejectedCount: rejectedCount ?? this.rejectedCount,
      lastDelivery: clearLastDelivery
          ? null
          : lastDelivery ?? this.lastDelivery,
    );
  }
}

final class ContributionController
    extends Notifier<ContributionControllerState> {
  final Set<String> _inFlightEventIds = {};
  Future<void> _deliveryTail = Future<void>.value();
  Timer? _retryTimer;
  String? _currentUserId;
  int _generation = 0;

  @override
  ContributionControllerState build() {
    final userId = ref.watch(authStateProvider).value?.id;
    final userChanged = userId != _currentUserId;
    _currentUserId = userId;
    ref.onDispose(() {
      _generation += 1;
      _retryTimer?.cancel();
    });
    Future<void>.microtask(() => _restore(userId, userChanged: userChanged));
    return const ContributionControllerState.idle();
  }

  Future<bool> recordAcceptedRep(ContributionRequest request) async {
    if (request.userId != _currentUserId ||
        !_inFlightEventIds.add(request.eventId)) {
      return false;
    }
    final completer = Completer<void>();
    _deliveryTail = _deliveryTail.catchError((Object _) {}).then((_) async {
      try {
        if (!ref.mounted || request.userId != _currentUserId) {
          return;
        }
        state = state.copyWith(
          isSubmitting: true,
          detectedCount: state.detectedCount + 1,
          clearLastDelivery: true,
        );
        final delivery = await ref
            .read(submitContributionProvider)
            .recordAcceptedRep(request);
        await _applyDelivery(delivery);
      } finally {
        _inFlightEventIds.remove(request.eventId);
        if (ref.mounted) {
          state = state.copyWith(isSubmitting: false);
        }
        completer.complete();
      }
    });
    await completer.future;
    return true;
  }

  Future<void> retryPending() => _flush(_currentUserId);

  Future<void> _restore(String? userId, {required bool userChanged}) async {
    final generation = ++_generation;
    _retryTimer?.cancel();
    _currentUserId = userId;
    if (userChanged) {
      _inFlightEventIds.clear();
    }
    if (userId == null) {
      if (ref.mounted) {
        state = const ContributionControllerState.idle();
      }
      return;
    }
    state = state.copyWith(isRestoring: true, clearLastDelivery: true);
    try {
      await _flush(userId, generation: generation);
    } finally {
      if (generation == _generation && ref.mounted) {
        state = state.copyWith(isRestoring: false);
      }
    }
  }

  Future<void> _flush(String? userId, {int? generation}) async {
    if (userId == null) {
      return;
    }
    final currentGeneration = generation ?? _generation;
    final deliveries = await ref
        .read(submitContributionProvider)
        .flushPending(userId);
    if (!ref.mounted ||
        currentGeneration != _generation ||
        userId != _currentUserId) {
      return;
    }
    for (final delivery in deliveries) {
      await _applyDelivery(delivery);
    }
    final pending = await ref
        .read(submitContributionProvider)
        .pendingCount(userId);
    if (ref.mounted && currentGeneration == _generation) {
      state = state.copyWith(pendingCount: pending);
      if (pending > 0) {
        _scheduleRetry();
      }
    }
  }

  Future<void> _applyDelivery(ContributionDelivery delivery) async {
    if (!ref.mounted || delivery.request.userId != _currentUserId) {
      return;
    }
    final pending = await ref
        .read(submitContributionProvider)
        .pendingCount(delivery.request.userId);
    state = state.copyWith(
      pendingCount: pending,
      confirmedCount:
          state.confirmedCount +
          (delivery.status == ContributionSyncStatus.confirmed ? 1 : 0),
      rejectedCount:
          state.rejectedCount +
          (delivery.status == ContributionSyncStatus.rejected ? 1 : 0),
      lastDelivery: delivery,
    );
    if (delivery.status == ContributionSyncStatus.pending) {
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_flush(_currentUserId));
    });
  }
}
