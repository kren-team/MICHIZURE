import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/contribution.dart';
import '../domain/contribution_repository.dart';

final class SharedPreferencesContributionOutbox implements ContributionOutbox {
  SharedPreferencesContributionOutbox([SharedPreferencesAsync? preferences])
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const int maximumPendingEvents = 100;
  static const String _storageKey = 'contribution_outbox_v1';

  final SharedPreferencesAsync _preferences;
  Future<void> _operationTail = Future<void>.value();

  @override
  Future<List<ContributionRequest>> loadForUser(String userId) {
    return _serialized(() async {
      if (userId.isEmpty) {
        throw const ContributionFailure(
          ContributionRejectionReason.invalidRequest,
        );
      }
      final entries = await _readAll();
      return entries
          .where((request) => request.userId == userId)
          .toList(growable: false);
    });
  }

  @override
  Future<void> put(ContributionRequest request) {
    return _serialized(() async {
      if (!request.isValid) {
        throw const ContributionFailure(
          ContributionRejectionReason.invalidRequest,
        );
      }
      final entries = await _readAll();
      final existingIndex = entries.indexWhere(
        (entry) => entry.eventId == request.eventId,
      );
      if (existingIndex >= 0) {
        if (!_sameRequest(entries[existingIndex], request)) {
          throw const ContributionFailure(ContributionRejectionReason.conflict);
        }
        return;
      }
      if (entries.length >= maximumPendingEvents) {
        throw const ContributionFailure(ContributionRejectionReason.outboxFull);
      }
      entries.add(request);
      entries.sort(_compareRequests);
      await _writeAndVerify(entries);
    });
  }

  @override
  Future<void> remove(String eventId) {
    return _serialized(() async {
      if (eventId.isEmpty) {
        throw const ContributionFailure(
          ContributionRejectionReason.invalidRequest,
        );
      }
      final entries = await _readAll();
      final removed = entries
          .where((entry) => entry.eventId != eventId)
          .toList(growable: true);
      if (removed.length == entries.length) {
        return;
      }
      await _writeAndVerify(removed);
    });
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationTail = _operationTail.catchError((Object _) {}).then((_) async {
      try {
        completer.complete(await operation());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<List<ContributionRequest>> _readAll() async {
    final encoded = await _preferences.getString(_storageKey);
    if (encoded == null) {
      return [];
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List<dynamic> || decoded.length > maximumPendingEvents) {
        throw const FormatException('invalid outbox');
      }
      return decoded.map(_requestFromJson).toList(growable: true)
        ..sort(_compareRequests);
    } on ContributionFailure {
      rethrow;
    } on Object {
      throw const ContributionFailure(
        ContributionRejectionReason.malformedData,
      );
    }
  }

  Future<void> _writeAndVerify(List<ContributionRequest> entries) async {
    final encoded = jsonEncode(
      entries.map(_requestToJson).toList(growable: false),
    );
    await _preferences.setString(_storageKey, encoded);
    final persisted = await _preferences.getString(_storageKey);
    if (persisted != encoded) {
      throw const ContributionFailure(ContributionRejectionReason.unknown);
    }
  }
}

Map<String, Object> _requestToJson(ContributionRequest request) {
  return {
    'debtId': request.debtId,
    'userId': request.userId,
    'eventId': request.eventId,
    'squatSessionId': request.squatSessionId,
    'sequence': request.sequence,
    'acceptedReps': request.acceptedReps,
    'detectorType': request.detectorType.wireValue,
    'detectorVersion': request.detectorVersion,
    'clientObservedAtEpochMs': request.clientObservedAt
        .toUtc()
        .millisecondsSinceEpoch,
  };
}

ContributionRequest _requestFromJson(Object? value) {
  const expectedKeys = {
    'debtId',
    'userId',
    'eventId',
    'squatSessionId',
    'sequence',
    'acceptedReps',
    'detectorType',
    'detectorVersion',
    'clientObservedAtEpochMs',
  };
  if (value is! Map<String, dynamic> ||
      value.keys.toSet().length != expectedKeys.length ||
      !value.keys.toSet().containsAll(expectedKeys)) {
    throw const ContributionFailure(ContributionRejectionReason.malformedData);
  }
  final detectorTypeValue = value['detectorType'];
  final detectorType = detectorTypeValue is String
      ? ContributionDetectorType.fromWireValue(detectorTypeValue)
      : null;
  final observedAt = value['clientObservedAtEpochMs'];
  if (value['debtId'] is! String ||
      value['userId'] is! String ||
      value['eventId'] is! String ||
      value['squatSessionId'] is! String ||
      value['sequence'] is! int ||
      value['acceptedReps'] is! int ||
      detectorType == null ||
      value['detectorVersion'] is! String ||
      observedAt is! int) {
    throw const ContributionFailure(ContributionRejectionReason.malformedData);
  }
  final request = ContributionRequest(
    debtId: value['debtId'] as String,
    userId: value['userId'] as String,
    eventId: value['eventId'] as String,
    squatSessionId: value['squatSessionId'] as String,
    sequence: value['sequence'] as int,
    acceptedReps: value['acceptedReps'] as int,
    detectorType: detectorType,
    detectorVersion: value['detectorVersion'] as String,
    clientObservedAt: DateTime.fromMillisecondsSinceEpoch(
      observedAt,
      isUtc: true,
    ),
  );
  if (!request.isValid) {
    throw const ContributionFailure(ContributionRejectionReason.malformedData);
  }
  return request;
}

int _compareRequests(ContributionRequest left, ContributionRequest right) {
  final byTime = left.clientObservedAt.compareTo(right.clientObservedAt);
  return byTime != 0 ? byTime : left.eventId.compareTo(right.eventId);
}

bool _sameRequest(ContributionRequest left, ContributionRequest right) {
  return _requestToJson(left).toString() == _requestToJson(right).toString();
}
