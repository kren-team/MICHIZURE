import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/profile/domain/profile_failure.dart';
import 'package:michizure/features/profile/infrastructure/firestore_profile_repository.dart';

void main() {
  final timestamp = Timestamp.fromDate(DateTime.utc(2026, 1, 1));

  Map<String, dynamic> validData() => {
    'displayName': 'Alice',
    'photoUrl': null,
    'groupId': null,
    'activeTaskSessionId': null,
    'createdAt': timestamp,
    'updatedAt': timestamp,
    'schemaVersion': 1,
  };

  test('converts a valid users document', () {
    final profile = userProfileFromFirestore('alice', validData());

    expect(profile.id, 'alice');
    expect(profile.displayName, 'Alice');
    expect(profile.createdAt, timestamp.toDate());
  });

  test('rejects an invalid users document', () {
    final data = validData()..['schemaVersion'] = 2;

    expect(
      () => userProfileFromFirestore('alice', data),
      throwsA(
        isA<ProfileFailure>().having(
          (failure) => failure.kind,
          'kind',
          ProfileFailureKind.invalidData,
        ),
      ),
    );
  });
}
