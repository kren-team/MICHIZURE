import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../debt/application/contribution_controller.dart';
import '../../debt/domain/contribution.dart';
import '../../debt/domain/debt.dart';
import '../domain/squat_detector.dart';

final squatSessionControllerProvider =
    NotifierProvider<SquatSessionController, SquatSessionState>(
      SquatSessionController.new,
    );

enum SquatSessionStatus {
  idle,
  requestingPermission,
  starting,
  running,
  stopping,
}

final class SquatSessionState {
  const SquatSessionState({
    required this.status,
    required this.permission,
    required this.detectorState,
    required this.detectedReps,
    required this.lastSequence,
    required this.maximumLocalReps,
    this.squatSessionId,
    this.debtId,
    this.qualityWarning,
    this.failure,
    this.lastAnalysisLatencyMs,
    this.diagnostics,
  });

  const SquatSessionState.initial()
    : status = SquatSessionStatus.idle,
      permission = CameraPermissionState.denied,
      detectorState = SquatDetectorState.calibrating,
      detectedReps = 0,
      lastSequence = 0,
      maximumLocalReps = 0,
      squatSessionId = null,
      debtId = null,
      qualityWarning = null,
      failure = null,
      lastAnalysisLatencyMs = null,
      diagnostics = null;

  final SquatSessionStatus status;
  final CameraPermissionState permission;
  final SquatDetectorState detectorState;
  final int detectedReps;
  final int lastSequence;
  final int maximumLocalReps;
  final String? squatSessionId;
  final String? debtId;
  final SquatQualityWarning? qualityWarning;
  final SquatDetectorFailure? failure;
  final int? lastAnalysisLatencyMs;
  final SquatDetectorDiagnostics? diagnostics;

  bool get isRunning => status == SquatSessionStatus.running;

  SquatSessionState copyWith({
    SquatSessionStatus? status,
    CameraPermissionState? permission,
    SquatDetectorState? detectorState,
    int? detectedReps,
    int? lastSequence,
    int? maximumLocalReps,
    String? squatSessionId,
    String? debtId,
    SquatQualityWarning? qualityWarning,
    SquatDetectorFailure? failure,
    int? lastAnalysisLatencyMs,
    SquatDetectorDiagnostics? diagnostics,
    bool clearSession = false,
    bool clearWarning = false,
    bool clearFailure = false,
  }) {
    return SquatSessionState(
      status: status ?? this.status,
      permission: permission ?? this.permission,
      detectorState: detectorState ?? this.detectorState,
      detectedReps: detectedReps ?? this.detectedReps,
      lastSequence: lastSequence ?? this.lastSequence,
      maximumLocalReps: maximumLocalReps ?? this.maximumLocalReps,
      squatSessionId: clearSession
          ? null
          : squatSessionId ?? this.squatSessionId,
      debtId: clearSession ? null : debtId ?? this.debtId,
      qualityWarning: clearWarning
          ? null
          : qualityWarning ?? this.qualityWarning,
      failure: clearFailure ? null : failure ?? this.failure,
      lastAnalysisLatencyMs:
          lastAnalysisLatencyMs ?? this.lastAnalysisLatencyMs,
      diagnostics: clearSession ? null : diagnostics ?? this.diagnostics,
    );
  }
}

final class SquatSessionController extends Notifier<SquatSessionState> {
  StreamSubscription<SquatDetectorEvent>? _eventSubscription;
  final Set<String> _processedRepEvents = {};
  bool _commandInFlight = false;
  bool _stopRequested = false;
  late SquatDetector _detector;
  String? _activeSessionId;

  @override
  SquatSessionState build() {
    _detector = ref.read(squatDetectorProvider);
    _eventSubscription = _detector.events.listen(
      _onEvent,
      onError: (Object error, StackTrace stackTrace) {
        if (!ref.mounted) return;
        state = state.copyWith(
          failure: error is SquatDetectorFailure
              ? error
              : const SquatDetectorFailure(
                  SquatDetectorFailureReason.nativeUnavailable,
                ),
        );
      },
    );
    ref.onDispose(() {
      _eventSubscription?.cancel();
      final sessionId = _activeSessionId;
      if (sessionId != null) {
        unawaited(
          _detector.stop(squatSessionId: sessionId).catchError((Object _) {}),
        );
      }
    });
    Future<void>.microtask(refreshPermission);
    return const SquatSessionState.initial();
  }

  Future<void> refreshPermission() async {
    try {
      final permission = await _detector.getCameraPermissionState();
      if (ref.mounted) {
        state = state.copyWith(permission: permission, clearFailure: true);
      }
    } on SquatDetectorFailure catch (failure) {
      if (ref.mounted) state = state.copyWith(failure: failure);
    }
  }

  Future<void> requestPermission() async {
    if (_commandInFlight) return;
    _commandInFlight = true;
    _stopRequested = false;
    state = state.copyWith(
      status: SquatSessionStatus.requestingPermission,
      clearFailure: true,
    );
    try {
      final permission = await _detector.requestCameraPermission();
      if (ref.mounted) {
        state = state.copyWith(
          status: SquatSessionStatus.idle,
          permission: permission,
        );
      }
    } on SquatDetectorFailure catch (failure) {
      if (ref.mounted) {
        state = state.copyWith(
          status: SquatSessionStatus.idle,
          failure: failure,
        );
      }
    } finally {
      _commandInFlight = false;
    }
  }

  Future<void> openAppSettings() => _detector.openAppSettings();

  Future<bool> start({
    required String debtId,
    required int remainingReps,
  }) async {
    if (_commandInFlight ||
        state.isRunning ||
        state.permission != CameraPermissionState.granted ||
        remainingReps <= 0) {
      return false;
    }
    _commandInFlight = true;
    _stopRequested = false;
    final sessionId = ref.read(squatSessionIdGeneratorProvider).generate();
    state = state.copyWith(
      status: SquatSessionStatus.starting,
      squatSessionId: sessionId,
      debtId: debtId,
      detectorState: SquatDetectorState.calibrating,
      detectedReps: 0,
      lastSequence: 0,
      maximumLocalReps: remainingReps,
      clearWarning: true,
      clearFailure: true,
    );
    try {
      await _detector.start(
        SquatDetectorSession(squatSessionId: sessionId, debtId: debtId),
      );
      if (!ref.mounted) return false;
      if (_stopRequested) {
        await _detector.stop(squatSessionId: sessionId);
        state = state.copyWith(
          status: SquatSessionStatus.idle,
          clearSession: true,
          clearWarning: true,
        );
        return false;
      }
      _activeSessionId = sessionId;
      state = state.copyWith(status: SquatSessionStatus.running);
      return true;
    } on SquatDetectorFailure catch (failure) {
      if (ref.mounted) {
        state = state.copyWith(
          status: SquatSessionStatus.idle,
          failure: failure,
          clearSession: true,
        );
      }
      return false;
    } finally {
      _commandInFlight = false;
    }
  }

  Future<void> stop() async {
    if (state.squatSessionId == null) return;
    if (_commandInFlight) {
      _stopRequested = true;
      return;
    }
    _commandInFlight = true;
    final sessionId = state.squatSessionId;
    state = state.copyWith(status: SquatSessionStatus.stopping);
    try {
      await _detector.stop(squatSessionId: sessionId);
      if (ref.mounted) {
        _activeSessionId = null;
        _stopRequested = false;
        _processedRepEvents.clear();
        state = state.copyWith(
          status: SquatSessionStatus.idle,
          clearSession: true,
          clearWarning: true,
        );
      }
    } on SquatDetectorFailure catch (failure) {
      if (ref.mounted) {
        state = state.copyWith(
          status: SquatSessionStatus.running,
          failure: failure,
        );
      }
    } finally {
      _commandInFlight = false;
    }
  }

  Future<void> stopForTerminalDebt(Debt debt) async {
    if (state.debtId == debt.id && debt.isTerminal) await stop();
  }

  void _onEvent(SquatDetectorEvent event) {
    if (!ref.mounted) return;
    final sessionId = state.squatSessionId;
    if (sessionId == null) return;
    switch (event) {
      case SquatDetectorReady():
        if (event.squatSessionId != sessionId) return;
        state = state.copyWith(clearFailure: true);
      case SquatStateChanged():
        if (event.squatSessionId != sessionId) return;
        state = state.copyWith(
          detectorState: event.state,
          lastAnalysisLatencyMs: event.analysisLatencyMs,
        );
      case SquatQualityChanged():
        if (event.squatSessionId != sessionId) return;
        state = state.copyWith(
          qualityWarning: event.warning,
          clearWarning: event.warning == null,
          lastAnalysisLatencyMs: event.analysisLatencyMs,
        );
      case SquatRepCompleted():
        if (event.squatSessionId != sessionId ||
            event.sequence <= state.lastSequence ||
            !_processedRepEvents.add(event.eventId) ||
            state.detectedReps >= state.maximumLocalReps) {
          return;
        }
        state = state.copyWith(
          detectedReps: state.detectedReps + 1,
          lastSequence: event.sequence,
          lastAnalysisLatencyMs: event.analysisLatencyMs,
        );
        unawaited(_recordRep(event));
      case SquatDetectorFailed():
        if (event.squatSessionId != sessionId) return;
        final reason = event.code == 'cameraUnavailable'
            ? SquatDetectorFailureReason.cameraUnavailable
            : SquatDetectorFailureReason.nativeUnavailable;
        state = state.copyWith(failure: SquatDetectorFailure(reason));
        if (reason == SquatDetectorFailureReason.cameraUnavailable) {
          unawaited(stop());
        }
      case SquatDetectorDiagnostics():
        if (event.squatSessionId != sessionId) return;
        state = state.copyWith(
          detectorState: event.state,
          lastAnalysisLatencyMs: event.analysisLatencyMs,
          diagnostics: event,
        );
    }
  }

  Future<void> _recordRep(SquatRepCompleted event) async {
    final userId = ref.read(authStateProvider).value?.id;
    final debtId = state.debtId;
    if (userId == null || debtId == null || !state.isRunning) return;
    await ref
        .read(contributionControllerProvider.notifier)
        .recordAcceptedRep(
          ContributionRequest(
            debtId: debtId,
            userId: userId,
            eventId: ContributionEventId.build(
              userId: userId,
              squatSessionId: event.squatSessionId,
              sequence: event.sequence,
            ),
            squatSessionId: event.squatSessionId,
            sequence: event.sequence,
            acceptedReps: ContributionRequest.acceptedRepsPerEvent,
            detectorType: ContributionDetectorType.mlkit,
            detectorVersion: event.detectorVersion,
            clientObservedAt: event.occurredAt,
          ),
        );
  }
}
