import '../domain/group_failure.dart';

String groupFailureMessage(Object error) {
  if (error is! GroupFailure) {
    return 'グループ操作に失敗しました。時間をおいて再試行してください。';
  }
  return switch (error.kind) {
    GroupFailureKind.invalidName => 'グループ名は制御文字を含めず、1〜50文字で入力してください。',
    GroupFailureKind.alreadyMember => 'すでにグループに所属しています。',
    GroupFailureKind.invalidInvite => '招待コードが正しくありません。',
    GroupFailureKind.inviteExpired => 'この招待コードは期限切れです。',
    GroupFailureKind.inviteRevoked => 'この招待コードは取り消されています。',
    GroupFailureKind.groupFull => 'このグループは40人に達しています。',
    GroupFailureKind.notMember => 'このグループのメンバーではありません。',
    GroupFailureKind.ownerMustTransfer => '退出する前に所有者を他のメンバーへ移譲してください。',
    GroupFailureKind.invalidTransferTarget => '所有者の移譲先を確認してください。',
    GroupFailureKind.offline => 'ネットワークに接続できません。接続を確認してください。',
    GroupFailureKind.conflict => '同時操作と競合しました。最新状態で再試行してください。',
    GroupFailureKind.rulesDenied => 'このグループ操作は許可されていません。',
    GroupFailureKind.invalidData ||
    GroupFailureKind.unknown => 'グループ操作に失敗しました。時間をおいて再試行してください。',
  };
}
