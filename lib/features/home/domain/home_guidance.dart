enum HomeNextAction {
  completeDeviceSetup,
  selectLockApps,
  viewDebts,
  startTask,
}

final class HomeGuidance {
  const HomeGuidance({
    required this.action,
    required this.title,
    required this.description,
  });

  final HomeNextAction action;
  final String title;
  final String description;

  static HomeGuidance derive({
    required bool deviceSetupLoaded,
    required bool deviceSetupReady,
    required int selectedAppCount,
    required int activeDebtCount,
  }) {
    if (!deviceSetupLoaded || !deviceSetupReady) {
      return const HomeGuidance(
        action: HomeNextAction.completeDeviceSetup,
        title: '端末セットアップを完了する',
        description: '約束を開始する前に、監視と封印に必要な端末状態を確認します。',
      );
    }
    if (selectedAppCount == 0) {
      return const HomeGuidance(
        action: HomeNextAction.selectLockApps,
        title: '封印するアプリを選ぶ',
        description: '約束に失敗したとき、利用できなくするアプリを1件以上選びます。',
      );
    }
    if (activeDebtCount > 0) {
      return HomeGuidance(
        action: HomeNextAction.viewDebts,
        title: '現在の負債を確認する',
        description: '$activeDebtCount件の負債をグループで返済できます。',
      );
    }
    return const HomeGuidance(
      action: HomeNextAction.startTask,
      title: '約束を開始する',
      description: '内容と時間を決めて、集中する約束を始めます。',
    );
  }
}
