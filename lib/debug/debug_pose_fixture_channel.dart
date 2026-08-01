import 'package:flutter/services.dart';

import '../features/squat/infrastructure/squat_detector_channel.dart';

final class DebugPoseFixtureResult {
  const DebugPoseFixtureResult({
    required this.callbackDelivered,
    required this.poseCount,
    required this.hipAvailable,
    required this.kneeAvailable,
    required this.ankleAvailable,
    required this.errorCode,
  });

  final bool callbackDelivered;
  final int poseCount;
  final bool hipAvailable;
  final bool kneeAvailable;
  final bool ankleAvailable;
  final String? errorCode;
}

abstract interface class DebugPoseFixtureGateway {
  Future<DebugPoseFixtureResult> run();
}

abstract interface class DebugPoseThumbnailGateway {
  Future<void> setEnabled(bool enabled);
}

final class MethodChannelDebugPoseFixtureGateway
    implements DebugPoseFixtureGateway, DebugPoseThumbnailGateway {
  MethodChannelDebugPoseFixtureGateway({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.kren.michizure/squat_control/v1');

  final MethodChannel _channel;

  @override
  Future<DebugPoseFixtureResult> run() async {
    final payload = await _channel.invokeMapMethod<Object?, Object?>(
      'runDebugPoseFixture',
      const {'contractVersion': MethodChannelSquatDetector.contractVersion},
    );
    if (payload == null ||
        payload['contractVersion'] !=
            MethodChannelSquatDetector.contractVersion ||
        payload['callbackDelivered'] is! bool ||
        payload['poseCount'] is! int ||
        payload['hipAvailable'] is! bool ||
        payload['kneeAvailable'] is! bool ||
        payload['ankleAvailable'] is! bool ||
        (payload['errorCode'] != null && payload['errorCode'] is! String)) {
      throw const FormatException('Malformed debug pose fixture result');
    }
    return DebugPoseFixtureResult(
      callbackDelivered: payload['callbackDelivered']! as bool,
      poseCount: payload['poseCount']! as int,
      hipAvailable: payload['hipAvailable']! as bool,
      kneeAvailable: payload['kneeAvailable']! as bool,
      ankleAvailable: payload['ankleAvailable']! as bool,
      errorCode: payload['errorCode'] as String?,
    );
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    final payload = await _channel
        .invokeMapMethod<Object?, Object?>('setDebugPoseThumbnailEnabled', {
          'contractVersion': MethodChannelSquatDetector.contractVersion,
          'enabled': enabled,
        });
    if (payload == null ||
        payload['contractVersion'] !=
            MethodChannelSquatDetector.contractVersion ||
        payload['enabled'] != enabled) {
      throw const FormatException('Malformed debug thumbnail result');
    }
  }
}
