import 'package:flutter/material.dart';

import '../domain/lockable_app.dart';

final class SelectedAppsSummary extends StatelessWidget {
  const SelectedAppsSummary({
    required this.apps,
    required this.selectedPackageNames,
    this.onManage,
    this.manageButtonKey,
    super.key,
  });

  final List<LockableApp> apps;
  final Set<String> selectedPackageNames;
  final VoidCallback? onManage;
  final Key? manageButtonKey;

  @override
  Widget build(BuildContext context) {
    final selectedApps = apps
        .where((app) => selectedPackageNames.contains(app.packageName))
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${selectedApps.length}件選択済み',
          key: const Key('selected-app-count'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          _labelSummary(selectedApps),
          key: const Key('selected-app-labels'),
        ),
        if (onManage case final manage?) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            key: manageButtonKey,
            onPressed: manage,
            icon: const Icon(Icons.tune),
            label: const Text('確認・変更'),
          ),
        ],
      ],
    );
  }
}

String _labelSummary(List<LockableApp> apps) {
  if (apps.isEmpty) {
    return '封印対象はまだ選択されていません';
  }
  final visible = apps.take(2).map((app) => app.label).join('、');
  final hiddenCount = apps.length - 2;
  return hiddenCount > 0 ? '$visible、ほか$hiddenCount件' : visible;
}
