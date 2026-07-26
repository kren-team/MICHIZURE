import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/group_invite.dart';
import '../domain/group_repository.dart';

final groupControllerProvider =
    NotifierProvider<GroupController, AsyncValue<IssuedGroupInvite?>>(
      GroupController.new,
    );

final class GroupController extends Notifier<AsyncValue<IssuedGroupInvite?>> {
  @override
  AsyncValue<IssuedGroupInvite?> build() => const AsyncData(null);

  GroupRepository get _repository => ref.read(groupRepositoryProvider);

  void clearResult() {
    if (!state.isLoading) {
      state = const AsyncData(null);
    }
  }

  Future<void> createGroup({
    required String userId,
    required String displayName,
    required String name,
  }) {
    return _submit(() async {
      await _repository.createGroup(
        userId: userId,
        displayName: displayName,
        name: name,
      );
      return null;
    });
  }

  Future<void> joinGroup({
    required String userId,
    required String displayName,
    required String rawInviteToken,
  }) {
    return _submit(() async {
      await _repository.joinGroup(
        userId: userId,
        displayName: displayName,
        rawInviteToken: rawInviteToken,
      );
      return null;
    });
  }

  Future<void> createInvite({required String userId, required String groupId}) {
    return _submit(
      () => _repository.createInvite(userId: userId, groupId: groupId),
    );
  }

  Future<void> revokeInvite({
    required String userId,
    required String tokenHash,
  }) {
    return _submit(() async {
      await _repository.revokeInvite(userId: userId, tokenHash: tokenHash);
      return null;
    });
  }

  Future<void> transferOwnership({
    required String userId,
    required String groupId,
    required String newOwnerUid,
  }) {
    return _submit(() async {
      await _repository.transferOwnership(
        userId: userId,
        groupId: groupId,
        newOwnerUid: newOwnerUid,
      );
      return null;
    });
  }

  Future<void> leaveGroup({required String userId, required String groupId}) {
    return _submit(() async {
      await _repository.leaveGroup(userId: userId, groupId: groupId);
      return null;
    });
  }

  Future<void> _submit(Future<IssuedGroupInvite?> Function() action) async {
    if (state.isLoading) {
      return;
    }
    state = const AsyncLoading();
    final result = await AsyncValue.guard(action);
    if (ref.mounted) {
      state = result;
    }
  }
}
