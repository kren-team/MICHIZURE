import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:michizure/features/enforcement/infrastructure/device_control_channel.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native device setup catalog and selection survive repository recreation',
    (tester) async {
      final repository = MethodChannelDeviceControlRepository();
      final capabilities = await repository.getCapabilities();
      final apps = await repository.listLockableApps();
      final originalSelection = await repository.getSelectedPackageNames();

      expect(capabilities.sdkInt, greaterThanOrEqualTo(23));
      expect(apps, isNotEmpty);
      final self = apps.singleWhere(
        (app) => app.packageName == 'com.kren.michizure',
      );
      expect(self.isSelectable, isFalse);

      final selected = apps
          .where((app) => app.isSelectable)
          .take(2)
          .map((app) => app.packageName)
          .toSet();
      expect(selected, isNotEmpty);

      try {
        expect(await repository.saveSelectedPackageNames(selected), selected);
        final recreatedRepository = MethodChannelDeviceControlRepository();
        expect(await recreatedRepository.getSelectedPackageNames(), selected);
      } finally {
        await repository.saveSelectedPackageNames(originalSelection);
      }
    },
  );
}
