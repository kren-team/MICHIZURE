import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../features/squat/domain/squat_detector.dart';
import '../features/squat/infrastructure/squat_detector_channel.dart';
import 'debug_pose_fixture_channel.dart';

/// Debug-only camera -> detector -> local count harness.
///
/// It intentionally has no Auth, Debt, Contribution, or Firestore dependency.
final class SquatLabScreen extends ConsumerStatefulWidget {
  const SquatLabScreen({super.key, this.fixtureGateway, this.thumbnailGateway});

  final DebugPoseFixtureGateway? fixtureGateway;
  final DebugPoseThumbnailGateway? thumbnailGateway;

  @override
  ConsumerState<SquatLabScreen> createState() => _SquatLabScreenState();
}

final class _SquatLabScreenState extends ConsumerState<SquatLabScreen> {
  static const _sessionId = 'squat-lab-debug-0001';
  static const _debtId = 'debug-squat-lab';

  StreamSubscription<SquatDetectorEvent>? _subscription;
  CameraPermissionState? _permission;
  SquatDetectorState _phase = SquatDetectorState.calibrating;
  SquatQualityWarning? _warning;
  final ValueNotifier<SquatDetectorDiagnostics?> _diagnostics = ValueNotifier(
    null,
  );
  SquatInferenceDelegate? _delegate;
  SquatPosePipelineStatus _pipelineStatus =
      SquatPosePipelineStatus.initializing;
  Object? _error;
  var _accepted = 0;
  var _running = false;
  var _fixtureRunning = false;
  var _thumbnailEnabled = false;
  DebugPoseFixtureResult? _fixtureResult;

  SquatDetector get _detector => ref.read(squatDetectorProvider);
  DebugPoseFixtureGateway get _fixtureGateway =>
      widget.fixtureGateway ?? MethodChannelDebugPoseFixtureGateway();
  DebugPoseThumbnailGateway get _thumbnailGateway =>
      widget.thumbnailGateway ?? MethodChannelDebugPoseFixtureGateway();

  @override
  void initState() {
    super.initState();
    assert(kDebugMode, 'Squat Lab must never run in release.');
    _subscription = _detector.events.listen(
      _onEvent,
      onError: (Object error, StackTrace _) {
        if (mounted) setState(() => _error = error);
      },
    );
    unawaited(_loadPermission());
  }

  Future<void> _loadPermission() async {
    final permission = await _detector.getCameraPermissionState();
    if (!mounted) return;
    setState(() => _permission = permission);
    if (permission == CameraPermissionState.granted) {
      await _start();
    }
  }

  Future<void> _requestPermission() async {
    final permission = await _detector.requestCameraPermission();
    if (!mounted) return;
    setState(() => _permission = permission);
    if (permission == CameraPermissionState.granted) await _start();
  }

  Future<void> _start() async {
    if (_running) return;
    try {
      await _detector.start(
        const SquatDetectorSession(squatSessionId: _sessionId, debtId: _debtId),
      );
      if (mounted) setState(() => _running = true);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _runFixture() async {
    if (_fixtureRunning) return;
    setState(() {
      _fixtureRunning = true;
      _fixtureResult = null;
    });
    try {
      final result = await _fixtureGateway.run();
      if (mounted) setState(() => _fixtureResult = result);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _fixtureRunning = false);
    }
  }

  Future<void> _setThumbnailEnabled(bool enabled) async {
    try {
      await _thumbnailGateway.setEnabled(enabled);
      if (mounted) setState(() => _thumbnailEnabled = enabled);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _onEvent(SquatDetectorEvent event) {
    if (!mounted) return;
    switch (event) {
      case SquatDetectorReady():
        setState(() => _delegate = event.delegate);
      case SquatStateChanged():
        setState(() => _phase = event.state);
      case SquatPipelineStatusChanged():
        setState(() => _pipelineStatus = event.status);
      case SquatQualityChanged():
        setState(() => _warning = event.warning);
      case SquatRepCompleted():
        setState(() => _accepted = event.sequence);
      case SquatDetectorDiagnostics():
        _diagnostics.value = event;
      case SquatDetectorFailed():
        setState(() => _error = event.code);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    if (_running) {
      unawaited(
        _detector.stop(squatSessionId: _sessionId).catchError((Object _) {}),
      );
    }
    _diagnostics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Squat Lab（Debug）')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_permission == CameraPermissionState.granted)
            const AspectRatio(
              aspectRatio: 3 / 4,
              child: AndroidView(
                key: Key('squat-lab-native-camera'),
                viewType: MethodChannelSquatDetector.previewViewType,
              ),
            )
          else
            FilledButton(
              key: const Key('squat-lab-permission'),
              onPressed: _permission == null ? null : _requestPermission,
              child: const Text('カメラを許可'),
            ),
          const SizedBox(height: 12),
          Text('Accepted: $_accepted', key: const Key('squat-lab-count')),
          Text('Phase: ${_phase.name}'),
          Text('Guidance: ${_warning?.name ?? 'ready'}'),
          Text('Delegate: ${_delegate?.name ?? 'initializing'}'),
          SwitchListTile(
            key: const Key('squat-lab-thumbnail-toggle'),
            contentPadding: EdgeInsets.zero,
            title: const Text('解析入力thumbnail（最大1 FPS）'),
            value: _thumbnailEnabled,
            onChanged: _setThumbnailEnabled,
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            key: const Key('squat-lab-run-fixture'),
            onPressed: _fixtureRunning ? null : _runFixture,
            child: Text(_fixtureRunning ? '既知画像を判定中…' : '既知画像でMediaPipeを確認'),
          ),
          if (_fixtureResult case final fixture?)
            Text(
              'Fixture callback/pose/H-K-A: '
              '${fixture.callbackDelivered} / ${fixture.poseCount} / '
              '${fixture.hipAvailable}-${fixture.kneeAvailable}-'
              '${fixture.ankleAvailable}'
              '${fixture.errorCode == null ? '' : ' (${fixture.errorCode})'}',
              key: const Key('squat-lab-fixture-result'),
            ),
          ValueListenableBuilder<SquatDetectorDiagnostics?>(
            valueListenable: _diagnostics,
            builder: (context, diagnostics, _) => _SquatLabDiagnosticsPanel(
              diagnostics: diagnostics,
              fallbackPipelineStatus: _pipelineStatus,
            ),
          ),
          if (_error != null)
            const Text('姿勢判定を開始できませんでした。', key: Key('squat-lab-error')),
        ],
      ),
    );
  }
}

final class _SquatLabDiagnosticsPanel extends StatelessWidget {
  const _SquatLabDiagnosticsPanel({
    required this.diagnostics,
    required this.fallbackPipelineStatus,
  });

  final SquatDetectorDiagnostics? diagnostics;
  final SquatPosePipelineStatus fallbackPipelineStatus;

  @override
  Widget build(BuildContext context) {
    final value = diagnostics;
    return Column(
      key: const Key('squat-lab-diagnostics'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pipeline: ${value?.pipelineStatus.name ?? fallbackPipelineStatus.name}',
        ),
        Text('Tracking: ${value?.trackingStatus.name ?? 'waiting'}'),
        Text('Side: ${value?.selectedSide?.name ?? 'none'}'),
        Text(
          'Raw / filtered knee: ${_metric(value?.rawKneeAngle)} / ${_metric(value?.kneeAngle)}',
        ),
        Text('Hip drop: ${_metric(value?.normalizedHipDrop, digits: 3)}'),
        Text(
          'Attempt min knee / max hip drop: ${_metric(value?.minimumAttemptKneeAngle)} / ${_metric(value?.maximumAttemptHipDrop, digits: 3)}',
        ),
        Text(
          'Knee bend / movement down-up: ${_metric(value?.kneeBendDelta)} / ${value?.downwardMovementObserved ?? false}-${value?.upwardMovementObserved ?? false}',
        ),
        Text(
          'Bottom evidence: ${value?.bottomEvidenceScore ?? 0} / ${_bottomPath(value?.bottomEvidencePath)}',
        ),
        Text(
          'Calibrated standing knee: ${_metric(value?.calibratedStandingKneeAngle)}',
        ),
        Text(
          'Threshold standing / descent / bottom / return: ${_metric(value?.standingThresholdDeg)} / ${_metric(value?.descendingThresholdDeg)} / ${_metric(value?.bottomThresholdDeg)} / ${_metric(value?.returnStandingThresholdDeg)}',
        ),
        Text(
          'Baseline hip / leg scale / jitter / side: ${_metric(value?.baselineHipY, digits: 3)} / ${_metric(value?.legScale, digits: 3)} / ${_metric(value?.baselineJitter, digits: 3)} / ${value?.calibrationSelectedSide?.name ?? '-'}',
        ),
        Text(
          'Phase path: ${value?.previousState?.name ?? '-'} → ${value?.state.name ?? '-'}',
        ),
        Text('Transition: ${value?.lastTransitionReason ?? 'none'}'),
        Text(
          'Reject / reset: ${value?.latestRejectReason ?? 'none'} / ${value?.lastResetReason ?? 'none'}',
        ),
        Text(
          'Frame dt / valid age: ${value?.frameDtMs ?? '-'} / ${value?.validPoseAgeMs ?? '-'} ms',
        ),
        Text(
          'Valid-pose FPS (FSM/pipeline): ${value?.effectiveValidPoseFps.toStringAsFixed(1) ?? '-'} / ${value?.validPoseFps.toStringAsFixed(1) ?? '-'}',
        ),
        Text(
          'Calibration: ${value?.calibrationStatus ?? 'waiting'} (${value?.calibrationSampleCount ?? 0}/8)',
        ),
        Text('Bottom reached: ${value?.bottomReached ?? false}'),
        Text(
          'Confirm standing / bottom / return: ${value?.standingConfirmationDurationMs ?? 0} / ${value?.bottomConfirmationDurationMs ?? 0} / ${value?.returnStandingDurationMs ?? 0} ms',
        ),
        Text('Current rep duration: ${value?.currentRepDurationMs ?? '-'} ms'),
        Text(
          'Accepted / rejected: ${value?.acceptedReps ?? 0} / ${value?.rejectedAttempts ?? 0}',
        ),
        Text(
          'Input / submit / callback / valid FPS: ${value?.analyzerInputFps.toStringAsFixed(1) ?? '-'} / ${value?.inferenceSubmittedFps.toStringAsFixed(1) ?? '-'} / ${value?.resultCallbackFps.toStringAsFixed(1) ?? '-'} / ${value?.validPoseFps.toStringAsFixed(1) ?? '-'}',
        ),
        Text(
          'Analysis requested / actual: ${value?.requestedAnalysisWidth ?? '-'}×${value?.requestedAnalysisHeight ?? '-'} / ${value?.actualAnalysisWidth ?? '-'}×${value?.actualAnalysisHeight ?? '-'}',
        ),
        Text(
          'Preprocess p50/p95: ${value?.preprocessingP50Ms ?? '-'} / ${value?.preprocessingP95Ms ?? '-'} ms',
        ),
        Text(
          'Inference p50/p95: ${value?.inferenceP50Ms ?? '-'} / ${value?.inferenceP95Ms ?? '-'} ms',
        ),
        Text(
          'Pipeline p50/p95: ${value?.nativePipelineP50Ms ?? '-'} / ${value?.nativePipelineP95Ms ?? '-'} ms',
        ),
        Text(
          'Throttle/busy drop: ${value?.droppedBeforePreprocessing ?? 0} / ${value?.rejectedAsBusy ?? 0}',
        ),
        Text(
          'Bitmap converted / rotated: ${value?.convertedBitmapCount ?? 0} / ${value?.rotationBitmapCount ?? 0}',
        ),
        Text(
          'Analyzer/submitted/callbacks: ${value?.analyzerFrames ?? 0} / ${value?.inferenceSubmitted ?? 0} / ${value?.resultCallbacks ?? 0}',
        ),
        Text(
          'Pose/no-pose/errors: ${value?.resultsWithPose ?? 0} / ${value?.resultsWithoutPose ?? 0} / ${value?.errorCallbacks ?? 0}',
        ),
        Text('Callback age: ${value?.lastCallbackAgeMs ?? '-'} ms'),
        Text('Last error: ${value?.lastError ?? 'none'}'),
      ],
    );
  }

  String _metric(double? value, {int digits = 2}) =>
      value?.toStringAsFixed(digits) ?? '-';

  String _bottomPath(SquatBottomEvidencePath? path) => switch (path) {
    SquatBottomEvidencePath.kneeOnly => 'KNEE_ONLY',
    SquatBottomEvidencePath.kneeAndHip => 'KNEE_AND_HIP',
    SquatBottomEvidencePath.hipAndReversal => 'HIP_AND_REVERSAL',
    null => 'none',
  };
}
