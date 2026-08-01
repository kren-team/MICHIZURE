import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../core/time/clock.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/auth/domain/auth_user.dart';
import '../features/auth/infrastructure/firebase_auth_repository.dart';
import '../features/debt/application/submit_contribution.dart';
import '../features/debt/domain/contribution_repository.dart';
import '../features/debt/domain/debt.dart';
import '../features/debt/domain/debt_repository.dart';
import '../features/debt/infrastructure/firestore_contribution_repository.dart';
import '../features/debt/infrastructure/firestore_debt_repository.dart';
import '../features/debt/infrastructure/shared_preferences_contribution_outbox.dart';
import '../features/enforcement/domain/device_control_repository.dart';
import '../features/enforcement/domain/app_lock_repository.dart';
import '../features/enforcement/infrastructure/app_lock_channel.dart';
import '../features/enforcement/infrastructure/device_control_channel.dart';
import '../features/group/domain/group.dart';
import '../features/group/domain/group_invite.dart';
import '../features/group/domain/group_member.dart';
import '../features/group/domain/group_repository.dart';
import '../features/group/infrastructure/firestore_group_repository.dart';
import '../features/group/infrastructure/secure_invite_token_generator.dart';
import '../features/notifications/application/notifying_task_repository.dart';
import '../features/notifications/domain/push_notifications.dart';
import '../features/notifications/infrastructure/firebase_push_messaging_gateway.dart';
import '../features/notifications/infrastructure/firestore_device_registration_repository.dart';
import '../features/notifications/infrastructure/http_notification_event_publisher.dart';
import '../features/notifications/infrastructure/shared_preferences_device_id_store.dart';
import '../features/profile/domain/profile_repository.dart';
import '../features/profile/domain/user_profile.dart';
import '../features/profile/infrastructure/firestore_profile_repository.dart';
import '../features/recovery/application/recovery_coordinator.dart';
import '../features/recovery/application/auth_revalidation_gate.dart';
import '../features/recovery/domain/recovery.dart';
import '../features/recovery/infrastructure/firebase_recovery_auth_gateway.dart';
import '../features/recovery/infrastructure/firestore_recovery_remote_store.dart';
import '../features/squat/domain/squat_detector.dart';
import '../features/squat/infrastructure/secure_squat_session_id_generator.dart';
import '../features/squat/infrastructure/squat_detector_channel.dart';
import '../features/task/application/start_task.dart';
import '../features/task/application/task_event_id_generator.dart';
import '../features/task/domain/native_task_guard.dart';
import '../features/task/domain/task_repository.dart';
import '../features/task/domain/task_session.dart';
import '../features/task/infrastructure/firestore_task_repository.dart';
import '../features/task/infrastructure/native_task_guard_channel.dart';
import '../features/task/infrastructure/secure_task_event_id_generator.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return FirebaseAuthRepository(ref.watch(firebaseAuthProvider));
});

final authStateProvider = StreamProvider<AuthUser?>((ref) {
  final authGateway = ref.watch(recoveryAuthGatewayProvider);
  return ref.watch(authRepositoryProvider).authStateChanges().asyncMap((
    user,
  ) async {
    if (user == null) {
      return null;
    }
    final result = await authGateway.recoverSession();
    return switch (result.status) {
      RecoveryAuthStatus.authenticated when result.userId == user.id => user,
      RecoveryAuthStatus.signedOut ||
      RecoveryAuthStatus.invalidCredentialSignedOut => null,
      RecoveryAuthStatus.temporarilyUnavailable =>
        throw const AuthSessionValidationFailure(),
      RecoveryAuthStatus.authenticated =>
        throw const AuthSessionValidationFailure(),
    };
  });
});

final deviceControlRepositoryProvider = Provider<DeviceControlRepository>((
  ref,
) {
  return MethodChannelDeviceControlRepository();
});

final appLockRepositoryProvider = Provider<AppLockRepository>((ref) {
  return MethodChannelAppLockRepository();
});

final firebaseFirestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final pushMessagingGatewayProvider = Provider<PushMessagingGateway>((ref) {
  return FirebasePushMessagingGateway(FirebaseMessaging.instance);
});

final deviceIdStoreProvider = Provider<DeviceIdStore>((ref) {
  return SharedPreferencesDeviceIdStore();
});

final deviceRegistrationRepositoryProvider =
    Provider<DeviceRegistrationRepository>((ref) {
      return FirestoreDeviceRegistrationRepository(
        ref.watch(firebaseFirestoreProvider),
      );
    });

final notificationEventPublisherProvider = Provider<NotificationEventPublisher>(
  (ref) {
    const baseUrl = String.fromEnvironment('NOTIFICATION_API_BASE_URL');
    return BestEffortNotificationEventPublisher(
      HttpNotificationEventPublisher(
        auth: ref.watch(firebaseAuthProvider),
        baseUrl: baseUrl,
      ),
    );
  },
);

final clockProvider = Provider<Clock>((ref) => const SystemClock());

final recoveryAuthGatewayProvider = Provider<RecoveryAuthGateway>((ref) {
  return FirebaseRecoveryAuthGateway(
    FlutterFireAuthSessionClient(ref.watch(firebaseAuthProvider)),
  );
});

final recoveryRemoteStoreProvider = Provider<RecoveryRemoteStore>((ref) {
  return FirestoreRecoveryRemoteStore(ref.watch(firebaseFirestoreProvider));
});

final debtRepositoryProvider = Provider<DebtRepository>((ref) {
  return FirestoreDebtRepository(ref.watch(firebaseFirestoreProvider));
});

final contributionRepositoryProvider = Provider<ContributionRepository>((ref) {
  return FirestoreContributionRepository(
    ref.watch(firebaseFirestoreProvider),
    ref.watch(clockProvider),
  );
});

final contributionOutboxProvider = Provider<ContributionOutbox>((ref) {
  return SharedPreferencesContributionOutbox();
});

final submitContributionProvider = Provider<SubmitContribution>((ref) {
  return SubmitContribution(
    ref.watch(contributionRepositoryProvider),
    ref.watch(contributionOutboxProvider),
    ref.watch(notificationEventPublisherProvider),
  );
});

final squatDetectorProvider = Provider<SquatDetector>((ref) {
  return MethodChannelSquatDetector();
});

final squatSessionIdGeneratorProvider = Provider<SquatSessionIdGenerator>((
  ref,
) {
  return SecureSquatSessionIdGenerator();
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return FirestoreProfileRepository(ref.watch(firebaseFirestoreProvider));
});

final currentProfileProvider = StreamProvider<UserProfile?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) {
    return Stream.value(null);
  }
  return _withAuthRevalidation(
    ref,
    ref.watch(profileRepositoryProvider).watchProfile(user.id),
  );
});

final inviteTokenGeneratorProvider = Provider<InviteTokenGenerator>((ref) {
  return SecureInviteTokenGenerator();
});

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  return FirestoreGroupRepository(
    ref.watch(firebaseFirestoreProvider),
    ref.watch(inviteTokenGeneratorProvider),
  );
});

final currentGroupProvider = StreamProvider<Group?>((ref) {
  final groupId = ref.watch(currentProfileProvider).value?.groupId;
  if (groupId == null) {
    return Stream.value(null);
  }
  return _withAuthRevalidation(
    ref,
    ref.watch(groupRepositoryProvider).watchGroup(groupId),
  );
});

final currentGroupMembersProvider = StreamProvider<List<GroupMember>>((ref) {
  final groupId = ref.watch(currentProfileProvider).value?.groupId;
  if (groupId == null) {
    return Stream.value(const []);
  }
  return _withAuthRevalidation(
    ref,
    ref.watch(groupRepositoryProvider).watchMembers(groupId),
  );
});

final activeGroupDebtsProvider =
    StreamProvider.autoDispose<DebtSnapshot<List<Debt>>>((ref) {
      final profile = ref.watch(currentProfileProvider);
      return profile.when(
        loading: () => const Stream.empty(),
        error: (error, stackTrace) => Stream.error(error, stackTrace),
        data: (value) {
          final groupId = value?.groupId;
          if (groupId == null) {
            return Stream.value(
              const DebtSnapshot(
                value: <Debt>[],
                isFromCache: false,
                hasPendingWrites: false,
              ),
            );
          }
          return _withAuthRevalidation(
            ref,
            ref.watch(debtRepositoryProvider).watchActiveDebts(groupId),
          );
        },
      );
    });

final debtProvider = StreamProvider.autoDispose
    .family<DebtSnapshot<Debt?>, String>((ref, debtId) {
      return _withAuthRevalidation(
        ref,
        ref.watch(debtRepositoryProvider).watchDebt(debtId),
      );
    });

final debtContributionsProvider = StreamProvider.autoDispose
    .family<DebtSnapshot<List<DebtContributionSummary>>, String>((ref, debtId) {
      return _withAuthRevalidation(
        ref,
        ref.watch(debtRepositoryProvider).watchContributions(debtId),
      );
    });

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return NotifyingTaskRepository(
    FirestoreTaskRepository(
      ref.watch(firebaseFirestoreProvider),
      ref.watch(clockProvider),
    ),
    ref.watch(notificationEventPublisherProvider),
  );
});

final taskEventIdGeneratorProvider = Provider<TaskEventIdGenerator>((ref) {
  return SecureTaskEventIdGenerator();
});

final nativeTaskGuardProvider = Provider<NativeTaskGuard>((ref) {
  return MethodChannelNativeTaskGuard();
});

final startTaskProvider = Provider<StartTask>((ref) {
  return StartTask(
    ref.watch(taskRepositoryProvider),
    ref.watch(deviceControlRepositoryProvider),
    ref.watch(nativeTaskGuardProvider),
  );
});

final recoveryCoordinatorProvider = Provider<RecoveryCoordinator>((ref) {
  return RecoveryCoordinator(
    authGateway: ref.watch(recoveryAuthGatewayProvider),
    remoteStore: ref.watch(recoveryRemoteStoreProvider),
    taskRepository: ref.watch(taskRepositoryProvider),
    debtRepository: ref.watch(debtRepositoryProvider),
    nativeTaskGuard: ref.watch(nativeTaskGuardProvider),
    appLockRepository: ref.watch(appLockRepositoryProvider),
    submitContribution: ref.watch(submitContributionProvider),
    clock: ref.watch(clockProvider),
  );
});

final authRevalidationGateProvider = Provider<AuthRevalidationGate>((ref) {
  return AuthRevalidationGate(() async {
    await ref
        .read(recoveryCoordinatorProvider)
        .run(RecoveryTrigger.authenticationRejected);
  });
});

final activeTaskSessionProvider = StreamProvider<TaskSession?>((ref) {
  final profile = ref.watch(currentProfileProvider);
  return profile.when(
    loading: () => const Stream.empty(),
    error: (error, stackTrace) => Stream.error(error, stackTrace),
    data: (value) {
      final taskId = value?.activeTaskSessionId;
      if (taskId == null) {
        return Stream.value(null);
      }
      return _withAuthRevalidation(
        ref,
        ref.watch(taskRepositoryProvider).watchTask(taskId),
      );
    },
  );
});

Stream<T> _withAuthRevalidation<T>(Ref ref, Stream<T> source) {
  return source.transform(
    StreamTransformer<T, T>.fromHandlers(
      handleError: (error, stackTrace, sink) {
        if (error is FirebaseException && error.code == 'unauthenticated') {
          unawaited(ref.read(authRevalidationGateProvider).request());
        }
        sink.addError(error, stackTrace);
      },
    ),
  );
}
