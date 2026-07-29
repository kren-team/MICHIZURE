import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/debt/domain/contribution.dart';

void main() {
  const userId = 'user123';
  const sessionId = '0123456789abcdef0123456789abcdef';

  test('builds a deterministic Contribution Event ID', () {
    expect(
      ContributionEventId.build(
        userId: userId,
        squatSessionId: sessionId,
        sequence: 7,
      ),
      'user123_0123456789abcdef0123456789abcdef_7',
    );
  });

  test('accepts exactly one confirmed rep with valid typed metadata', () {
    expect(_request().isValid, isTrue);
  });

  test('rejects invalid delta, event ID, session and sequence', () {
    expect(_request(acceptedReps: 0).isValid, isFalse);
    expect(_request(acceptedReps: 2).isValid, isFalse);
    expect(_request(eventId: 'forged').isValid, isFalse);
    expect(_request(squatSessionId: 'short').isValid, isFalse);
    expect(_request(sequence: 0).isValid, isFalse);
    expect(
      _request(sequence: ContributionRequest.maximumSequence + 1).isValid,
      isFalse,
    );
  });

  test('rejects document separators and invalid detector versions', () {
    expect(_request(debtId: 'debts/other').isValid, isFalse);
    expect(_request(detectorVersion: 'version with spaces').isValid, isFalse);
  });
}

ContributionRequest _request({
  String debtId = 'debt-1',
  String? eventId,
  String squatSessionId = '0123456789abcdef0123456789abcdef',
  int sequence = 1,
  int acceptedReps = 1,
  String detectorVersion = 'fsm-v1',
}) {
  const userId = 'user123';
  return ContributionRequest(
    debtId: debtId,
    userId: userId,
    eventId:
        eventId ??
        ContributionEventId.build(
          userId: userId,
          squatSessionId: squatSessionId,
          sequence: sequence,
        ),
    squatSessionId: squatSessionId,
    sequence: sequence,
    acceptedReps: acceptedReps,
    detectorType: ContributionDetectorType.mlkit,
    detectorVersion: detectorVersion,
    clientObservedAt: DateTime.utc(2026),
  );
}
