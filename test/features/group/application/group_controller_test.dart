import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/group/application/group_controller.dart';

import '../support/fake_group_repository.dart';

void main() {
  test('createGroup is single-flight', () async {
    final repository = FakeGroupRepository()
      ..createCompleter = Completer<void>();
    final container = ProviderContainer(
      overrides: [groupRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final controller = container.read(groupControllerProvider.notifier);
    final first = controller.createGroup(
      userId: 'alice',
      displayName: 'Alice',
      name: 'Group',
    );
    final second = controller.createGroup(
      userId: 'alice',
      displayName: 'Alice',
      name: 'Group',
    );

    expect(repository.createCalls, 1);
    repository.createCompleter!.complete();
    await Future.wait([first, second]);
  });

  test('joinGroup is single-flight', () async {
    final repository = FakeGroupRepository()..joinCompleter = Completer<void>();
    final container = ProviderContainer(
      overrides: [groupRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final controller = container.read(groupControllerProvider.notifier);
    final first = controller.joinGroup(
      userId: 'alice',
      displayName: 'Alice',
      rawInviteToken: 'token',
    );
    final second = controller.joinGroup(
      userId: 'alice',
      displayName: 'Alice',
      rawInviteToken: 'token',
    );

    expect(repository.joinCalls, 1);
    repository.joinCompleter!.complete();
    await Future.wait([first, second]);
  });
}
