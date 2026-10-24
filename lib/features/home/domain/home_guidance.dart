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
    required this.actionLabel,
  });

  final HomeNextAction action;
  final String title;
  final String description;

  /// CTAの文言。見出しと同じ文を繰り返さず、押した結果を動詞で示す。
  final String actionLabel;

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
        actionLabel: 'セットアップを開く',
      );
    }
    if (selectedAppCount == 0) {
      return const HomeGuidance(
        action: HomeNextAction.selectLockApps,
        title: '封印するアプリを選ぶ',
        description: '約束に失敗したとき、利用できなくするアプリを1件以上選びます。',
        actionLabel: 'アプリを選ぶ',
      );
    }
    if (activeDebtCount > 0) {
      return HomeGuidance(
        action: HomeNextAction.viewDebts,
        title: '現在の負債を確認する',
        description: '$activeDebtCount件の負債をグループで返済できます。',
        actionLabel: 'スクワットで返済する',
      );
    }
    return const HomeGuidance(
      action: HomeNextAction.startTask,
      title: '約束を開始する',
      description: '内容と時間を決めて、集中する約束を始めます。',
      actionLabel: '約束を始める',
    );
  }
}
