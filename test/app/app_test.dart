import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/app/app.dart';
import 'package:michizure/app/bootstrap.dart';

void main() {
  testWidgets('renders the bootstrap placeholder and environment', (
    tester,
  ) async {
    await tester.pumpWidget(
      MichizureApp(
        bootstrapState: BootstrapState(
          environment: AppEnvironment.firebaseEmulator,
          projectId: demoFirebaseProjectId,
          startedAt: DateTime.utc(2026),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bootstrap OK'), findsOneWidget);
    expect(find.text('Environment: Firebase Emulator'), findsOneWidget);
    expect(find.text('Project: demo-michizure'), findsOneWidget);
  });
}
