import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/auth/domain/auth_user.dart';
import 'package:michizure/features/debt/application/contribution_controller.dart';
import 'package:michizure/features/debt/application/submit_contribution.dart';
import 'package:michizure/features/debt/domain/contribution.dart';

import '../support/fake_contribution_repository.dart';

void main() {
  test('same event is single-flight at the controller boundary', () async {
    final repository = FakeContributionRepository()
      ..blocker = Completer<void>();
    final outbox = InMemoryContributionOutbox();
    final container = _container(repository, outbox);
    addTearDown(container.dispose);
    final controller = container.read(contributionControllerProvider.notifier);
    await _settle();
    final request = contributionRequest();

    final first = controller.recordAcceptedRep(request);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final second = controller.recordAcceptedRep(request);

    repository.blocker!.complete();
    final results = await Future.wait([first, second]);
    expect(repository.requests, hasLength(1));
    expect(results, [true, false]);
    final state = container.read(contributionControllerProvider);
    expect(state.confirmedCount, 1);
    expect(state.pendingCount, 0);
  });

  test('offline delivery is pending and manual retry confirms it', () async {
    final repository = FakeContributionRepository()
      ..failure = const ContributionFailure(
        ContributionRejectionReason.offline,
      );
    final outbox = InMemoryContributionOutbox();
    final container = _container(repository, outbox);
    addTearDown(container.dispose);
    final controller = container.read(contributionControllerProvider.notifier);
    await _settle();

    await controller.recordAcceptedRep(contributionRequest());
    expect(container.read(contributionControllerProvider).pendingCount, 1);

    repository.failure = null;
    await controller.retryPending();
    final state = container.read(contributionControllerProvider);
    expect(state.pendingCount, 0);
    expect(state.confirmedCount, 1);
  });

  test('restores a pending event after controller recreation', () async {
    final repository = FakeContributionRepository()
      ..failure = const ContributionFailure(
        ContributionRejectionReason.offline,
      );
    final outbox = InMemoryContributionOutbox();
    final request = contributionRequest();
    await outbox.put(request);

    final first = _container(repository, outbox);
    first.read(contributionControllerProvider);
    await _settle();
    expect(first.read(contributionControllerProvider).pendingCount, 1);
    first.dispose();

    repository.failure = null;
    final second = _container(repository, outbox);
    addTearDown(second.dispose);
    second.read(contributionControllerProvider);
    await _settle();
    expect(second.read(contributionControllerProvider).pendingCount, 0);
    expect(repository.committed, contains(request.eventId));
  });

  test('terminal rejection is exposed as typed state', () async {
    final repository = FakeContributionRepository()
      ..failure = const ContributionFailure(
        ContributionRejectionReason.debtTerminal,
      );
    final container = _container(repository, InMemoryContributionOutbox());
    addTearDown(container.dispose);
    final controller = container.read(contributionControllerProvider.notifier);
    await _settle();

    await controller.recordAcceptedRep(contributionRequest());

    final state = container.read(contributionControllerProvider);
    expect(state.rejectedCount, 1);
    expect(
      state.lastDelivery?.failure?.reason,
      ContributionRejectionReason.debtTerminal,
    );
  });
}

ProviderContainer _container(
  FakeContributionRepository repository,
  InMemoryContributionOutbox outbox,
) {
  return ProviderContainer(
    overrides: [
      authStateProvider.overrideWithValue(
        const AsyncData(AuthUser(id: 'alice')),
      ),
      submitContributionProvider.overrideWithValue(
        SubmitContribution(repository, outbox),
      ),
    ],
  );
}

Future<void> _settle() async {
  for (var index = 0; index < 5; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}
