import '../domain/enforcement_failure.dart';

String enforcementFailureMessage(Object error) {
  final kind = error is EnforcementFailure
      ? error.kind
      : EnforcementFailureKind.unknown;
  return switch (kind) {
    EnforcementFailureKind.channelContractMismatch =>
      'アプリとAndroid機能のバージョンが一致しません。アプリを更新してください。',
    EnforcementFailureKind.packageProtected => '端末に必要なアプリは封印対象にできません。',
    EnforcementFailureKind.packageNotInstalled =>
      '選択したアプリが見つかりません。一覧を更新してください。',
    EnforcementFailureKind.nativeStateCorrupt => '端末内の選択状態を読み書きできませんでした。',
    EnforcementFailureKind.timeout => 'Android機能から応答がありません。もう一度お試しください。',
    EnforcementFailureKind.unsupportedPlatform => 'この機能はAndroid端末でのみ利用できます。',
    EnforcementFailureKind.nativeUnavailable ||
    EnforcementFailureKind.invalidData ||
    EnforcementFailureKind.unknown => '端末のセットアップ情報を取得できませんでした。',
  };
}
