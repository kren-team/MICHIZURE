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
  const SquatLabScreen({super.key, this.fixtureGateway});

  final DebugPoseFixtureGateway? fixtureGateway;

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
  SquatDetectorDiagnostics? _diagnostics;
  SquatInferenceDelegate? _delegate;
  SquatPosePipelineStatus _pipelineStatus =
      SquatPosePipelineStatus.initializing;
  Object? _error;
  var _accepted = 0;
  var _running = false;
  var _fixtureRunning = false;
  DebugPoseFixtureResult? _fixtureResult;

  SquatDetector get _detector => ref.read(squatDetectorProvider);
  DebugPoseFixtureGateway get _fixtureGateway =>
      widget.fixtureGateway ?? MethodChannelDebugPoseFixtureGateway();

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
        setState(() {
          _diagnostics = event;
          _phase = event.state;
          _accepted = event.acceptedReps;
        });
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final diagnostics = _diagnostics;
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
          Text(
            'Pipeline: ${diagnostics?.pipelineStatus.name ?? _pipelineStatus.name}',
          ),
          Text('Tracking: ${diagnostics?.trackingStatus.name ?? 'waiting'}'),
          Text('Side: ${diagnostics?.selectedSide?.name ?? 'none'}'),
          Text('Knee angle: ${_value(diagnostics?.kneeAngle)}'),
          Text('Hip drop: ${_value(diagnostics?.normalizedHipDrop)}'),
          Text(
            'Accepted / rejected: '
            '${diagnostics?.acceptedReps ?? 0} / '
            '${diagnostics?.rejectedAttempts ?? 0}',
          ),
          Text(
            'Analysis FPS: '
            '${diagnostics?.actualAnalysisFps.toStringAsFixed(1) ?? '-'}',
          ),
          Text(
            'Inference p50/p95: '
            '${diagnostics?.inferenceP50Ms ?? '-'} / '
            '${diagnostics?.inferenceP95Ms ?? '-'} ms',
          ),
          Text(
            'Pipeline p50/p95: '
            '${diagnostics?.nativePipelineP50Ms ?? '-'} / '
            '${diagnostics?.nativePipelineP95Ms ?? '-'} ms',
          ),
          Text(
            'Throttle/busy drop: '
            '${diagnostics?.droppedBeforePreprocessing ?? 0} / '
            '${diagnostics?.rejectedAsBusy ?? 0}',
          ),
          Text(
            'Analyzer/submitted/callbacks: '
            '${diagnostics?.analyzerFrames ?? 0} / '
            '${diagnostics?.inferenceSubmitted ?? 0} / '
            '${diagnostics?.resultCallbacks ?? 0}',
          ),
          Text(
            'Pose/no-pose/errors: '
            '${diagnostics?.resultsWithPose ?? 0} / '
            '${diagnostics?.resultsWithoutPose ?? 0} / '
            '${diagnostics?.errorCallbacks ?? 0}',
          ),
          Text('Callback age: ${diagnostics?.lastCallbackAgeMs ?? '-'} ms'),
          Text('Last error: ${diagnostics?.lastError ?? 'none'}'),
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
          if (_error != null)
            const Text('姿勢判定を開始できませんでした。', key: Key('squat-lab-error')),
        ],
      ),
    );
  }

  String _value(double? value) => value?.toStringAsFixed(2) ?? '-';
}
