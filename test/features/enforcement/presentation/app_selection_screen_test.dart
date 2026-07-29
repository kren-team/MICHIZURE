import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/providers.dart';
import 'package:michizure/features/enforcement/domain/enforcement_failure.dart';
import 'package:michizure/features/enforcement/presentation/app_selection/app_selection_screen.dart';

import '../support/fake_device_control_repository.dart';

void main() {
  testWidgets('selects, unselects, saves, and restores local app choices', (
    tester,
  ) async {
    final repository = FakeDeviceControlRepository()
      ..selectedPackageNames = {'social.app'};
    await _pump(tester, repository);

    expect(_checkbox(tester, 'social.app').value, isTrue);
    expect(_checkbox(tester, 'video.app').value, isFalse);

    await tester.tap(find.byKey(const Key('app-selection-video.app')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('app-selection-social.app')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('app-selection-save-button')));
    await tester.pumpAndSettle();

    expect(repository.selectedPackageNames, {'video.app'});
    expect(find.text('封印対象を保存しました'), findsOneWidget);

    await _pump(tester, repository);
    expect(_checkbox(tester, 'video.app').value, isTrue);
    expect(_checkbox(tester, 'social.app').value, isFalse);
  });

  testWidgets('disables protected packages with a reason', (tester) async {
    await _pump(tester, FakeDeviceControlRepository());

    final self = _checkbox(tester, 'com.kren.michizure');
    expect(self.onChanged, isNull);
    expect(find.text('MICHIZURE自身は選択できません'), findsOneWidget);
  });

  testWidgets('shows a safe typed error when local save fails', (tester) async {
    final repository = FakeDeviceControlRepository()
      ..saveError = const EnforcementFailure(
        EnforcementFailureKind.nativeStateCorrupt,
      );
    await _pump(tester, repository);

    await tester.tap(find.byKey(const Key('app-selection-social.app')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('app-selection-save-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-selection-save-error')), findsOneWidget);
    expect(find.textContaining('Firebase'), findsNothing);
    expect(repository.selectedPackageNames, isEmpty);
  });
}

CheckboxListTile _checkbox(WidgetTester tester, String packageName) {
  return tester.widget<CheckboxListTile>(
    find.byKey(Key('app-selection-$packageName')),
  );
}

Future<void> _pump(
  WidgetTester tester,
  FakeDeviceControlRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceControlRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(home: AppSelectionScreen()),
    ),
  );
  await tester.pumpAndSettle();
}
