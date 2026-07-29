import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/features/home/domain/home_guidance.dart';

void main() {
  group('HomeGuidance', () {
    test('requires device setup before every other action', () {
      final guidance = HomeGuidance.derive(
        deviceSetupLoaded: true,
        deviceSetupReady: false,
        selectedAppCount: 0,
        activeDebtCount: 2,
      );

      expect(guidance.action, HomeNextAction.completeDeviceSetup);
      expect(guidance.title, '端末セットアップを完了する');
    });

    test('requires a lock target after device setup', () {
      final guidance = HomeGuidance.derive(
        deviceSetupLoaded: true,
        deviceSetupReady: true,
        selectedAppCount: 0,
        activeDebtCount: 2,
      );

      expect(guidance.action, HomeNextAction.selectLockApps);
      expect(guidance.title, '封印するアプリを選ぶ');
    });

    test('prioritizes an active debt after setup is complete', () {
      final guidance = HomeGuidance.derive(
        deviceSetupLoaded: true,
        deviceSetupReady: true,
        selectedAppCount: 1,
        activeDebtCount: 2,
      );

      expect(guidance.action, HomeNextAction.viewDebts);
      expect(guidance.description, contains('2件'));
    });

    test('starts a task when all prerequisites are satisfied', () {
      final guidance = HomeGuidance.derive(
        deviceSetupLoaded: true,
        deviceSetupReady: true,
        selectedAppCount: 1,
        activeDebtCount: 0,
      );

      expect(guidance.action, HomeNextAction.startTask);
      expect(guidance.title, '約束を開始する');
    });
  });
}
