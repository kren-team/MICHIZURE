import '../domain/task_failure.dart';

String taskFailureMessage(Object error) {
  final kind = error is TaskFailure ? error.kind : TaskFailureKind.unknown;
  return switch (kind) {
    TaskFailureKind.invalidContent => '内容は1〜100文字で入力してください。',
    TaskFailureKind.invalidDuration => '実行時間は1〜180分で指定してください。',
    TaskFailureKind.notAuthenticated => 'ログイン状態を確認してください。',
    TaskFailureKind.groupRequired => '約束を開始するにはグループへの所属が必要です。',
    TaskFailureKind.deviceNotReady =>
      '端末セットアップが完了していません。Device Setupを確認してください。',
    TaskFailureKind.noLockTargets => '封印対象アプリを1件以上選択してください。',
    TaskFailureKind.alreadyActive => 'すでに実行中のTaskがあります。',
    TaskFailureKind.noActiveTask => '実行中の約束を復元できませんでした。',
    TaskFailureKind.notRunning => 'このTaskはすでに終了しています。',
    TaskFailureKind.deadlineNotReached => '終了時刻になるまで完了できません。',
    TaskFailureKind.conflict => '同時更新を検出しました。状態を再読み込みしてください。',
    TaskFailureKind.offline => '約束の更新にはネットワーク接続が必要です。',
    TaskFailureKind.rulesDenied => 'この約束を更新する権限がありません。',
    TaskFailureKind.invalidData => '約束のデータを確認できません。再読み込みしてください。',
    TaskFailureKind.unknown => '約束を更新できませんでした。もう一度お試しください。',
  };
}
