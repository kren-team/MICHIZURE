import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:michizure/core/presentation/app_components.dart';
import 'package:michizure/core/presentation/app_theme.dart';

void main() {
  test('uses the shared dark color system', () {
    final theme = buildMichizureTheme();

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, MichizureColors.background);
    expect(theme.colorScheme.primary, MichizureColors.purple);
    expect(theme.colorScheme.secondary, MichizureColors.pink);
    expect(theme.cardTheme.color, MichizureColors.surface);
  });

  testWidgets('gradient primary button keeps a full-size tap target', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMichizureTheme(),
        home: Scaffold(
          body: MichizurePrimaryButton(
            buttonKey: const Key('primary-action'),
            onPressed: () => taps += 1,
            child: const Text('開始する'),
          ),
        ),
      ),
    );

    final button = find.byKey(const Key('primary-action'));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    await tester.tap(button);
    expect(taps, 1);
  });
}
