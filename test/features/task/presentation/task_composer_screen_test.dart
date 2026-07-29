import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/auth/domain/auth_user.dart';
import 'package:michizure/features/profile/domain/user_profile.dart';
import 'package:michizure/features/task/domain/task_failure.dart';
import 'package:michizure/features/task/presentation/task_composer_screen.dart';

import '../../enforcement/support/fake_device_control_repository.dart';
import '../support/fake_task_repository.dart';
import '../support/fake_native_task_guard.dart';

void main() {
  testWidgets('starts a valid Unicode Task after a ready preflight', (
    tester,
  ) async {
    final tasks = FakeTaskRepository();
    final router = await _pumpComposer(tester, tasks: tasks);

    await tester.enterText(
      find.byKey(const Key('task-content-field')),
      '数学の課題',
    );
    await tester.tap(find.byKey(const Key('task-start-button')));
    await tester.pump();
    await tester.pump();

    expect(tasks.startCalls, 1);
    expect(tasks.lastStartRequest?.content, '数学の課題');
    expect(router.routeInformationProvider.value.uri.path, '/task/running');
  });

  testWidgets('shows local validation for invalid content', (tester) async {
    final tasks = FakeTaskRepository();
    await _pumpComposer(tester, tasks: tasks);

    await tester.enterText(find.byKey(const Key('task-content-field')), '   ');
    await tester.tap(find.byKey(const Key('task-start-button')));
    await tester.pump();

    expect(find.text('1〜100文字で入力してください'), findsOneWidget);
    expect(tasks.startCalls, 0);
  });

  testWidgets('renders a safe typed failure without an SDK message', (
    tester,
  ) async {
    final tasks = FakeTaskRepository()
      ..startError = const TaskFailure(TaskFailureKind.offline);
    await _pumpComposer(tester, tasks: tasks);

    await tester.enterText(
      find.byKey(const Key('task-content-field')),
      'Read paper',
    );
    await tester.tap(find.byKey(const Key('task-start-button')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('task-command-error')), findsOneWidget);
    expect(find.textContaining('ネットワーク'), findsOneWidget);
    expect(find.textContaining('Firebase'), findsNothing);
  });
}

Future<GoRouter> _pumpComposer(
  WidgetTester tester, {
  required FakeTaskRepository tasks,
}) async {
  final device = FakeDeviceControlRepository()
    ..selectedPackageNames = {'social.app'};
  final guard = FakeNativeTaskGuard();
  final router = GoRouter(
    initialLocation: '/task/new',
    routes: [
      GoRoute(
        path: '/task/new',
        builder: (context, state) => const TaskComposerScreen(),
      ),
      GoRoute(
        path: '/task/running',
        builder: (context, state) => const Scaffold(body: Text('Running')),
      ),
      GoRoute(
        path: '/device-setup',
        builder: (context, state) => const Scaffold(body: Text('Setup')),
      ),
    ],
  );
  addTearDown(router.dispose);
  addTearDown(guard.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        taskRepositoryProvider.overrideWithValue(tasks),
        deviceControlRepositoryProvider.overrideWithValue(device),
        nativeTaskGuardProvider.overrideWithValue(guard),
        authStateProvider.overrideWithValue(
          const AsyncData(AuthUser(id: 'alice')),
        ),
        currentProfileProvider.overrideWithValue(AsyncData(_profile)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump();
  return router;
}

final _profile = UserProfile(
  id: 'alice',
  displayName: 'Alice',
  photoUrl: null,
  groupId: 'group-1',
  activeTaskSessionId: null,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
