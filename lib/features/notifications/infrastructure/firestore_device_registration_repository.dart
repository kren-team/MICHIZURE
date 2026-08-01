import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/push_notifications.dart';

final class FirestoreDeviceRegistrationRepository
    implements DeviceRegistrationRepository {
  FirestoreDeviceRegistrationRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Future<void> upsert(DeviceRegistration registration) {
    return _firestore
        .collection('users')
        .doc(registration.userId)
        .collection('devices')
        .doc(registration.deviceId)
        .set({
          'token': registration.token,
          'platform': 'android',
          'updatedAt': FieldValue.serverTimestamp(),
          'enabled': true,
        });
  }

  @override
  Future<void> delete({required String userId, required String deviceId}) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('devices')
        .doc(deviceId)
        .delete();
  }
}
