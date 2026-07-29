import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/debt/domain/contribution.dart';
import 'package:michizure/features/debt/infrastructure/firestore_contribution_repository.dart';

void main() {
  const userId = 'user123';
  const sessionId = '0123456789abcdef0123456789abcdef';
  const eventId = 'user123_0123456789abcdef0123456789abcdef_1';

  test('converts a strict immutable Contribution Event', () {
    final event = contributionEventFromFirestore(eventId, {
      'userId': userId,
      'squatSessionId': sessionId,
      'sequence': 1,
      'acceptedReps': 1,
      'detectorType': 'mlkit',
      'detectorVersion': 'fsm-v1',
      'clientObservedAt': Timestamp.fromDate(DateTime.utc(2026)),
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1, 0, 0, 1)),
      'schemaVersion': 1,
    });

    expect(event.id, eventId);
    expect(event.detectorType, ContributionDetectorType.mlkit);
    expect(event.acceptedReps, 1);
  });

  test('rejects malformed identity, delta, detector and extra fields', () {
    final valid = <String, dynamic>{
      'userId': userId,
      'squatSessionId': sessionId,
      'sequence': 1,
      'acceptedReps': 1,
      'detectorType': 'mlkit',
      'detectorVersion': 'fsm-v1',
      'clientObservedAt': Timestamp.fromDate(DateTime.utc(2026)),
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1, 0, 0, 1)),
      'schemaVersion': 1,
    };
    for (final malformed in [
      {...valid, 'acceptedReps': 2},
      {...valid, 'detectorType': 'fake_debug'},
      {...valid, 'packageName': 'private.package'},
    ]) {
      expect(
        () => contributionEventFromFirestore(eventId, malformed),
        throwsA(isA<ContributionFailure>()),
      );
    }
    expect(
      () => contributionEventFromFirestore('forged', valid),
      throwsA(isA<ContributionFailure>()),
    );
  });

  test('maps Firebase transport and authorization failures safely', () {
    expect(
      mapContributionFailure(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      ).reason,
      ContributionRejectionReason.offline,
    );
    expect(
      mapContributionFailure(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      ).reason,
      ContributionRejectionReason.unauthorized,
    );
  });
}
