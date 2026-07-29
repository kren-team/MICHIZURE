import '../domain/debt_failure.dart';

String debtFailureMessage(Object error) {
  final kind = error is DebtFailure ? error.kind : DebtFailureKind.unknown;
  return switch (kind) {
    DebtFailureKind.invalidData => 'Debtデータを読み取れませんでした。',
    DebtFailureKind.notFound => 'Debtが見つかりません。',
    DebtFailureKind.rulesDenied => 'このDebtを表示する権限がありません。',
    DebtFailureKind.offline => 'オフラインです。接続後に自動で再同期します。',
    DebtFailureKind.conflict => '更新が競合しました。もう一度お試しください。',
    DebtFailureKind.nativeReleaseFailed => '封印解除を端末へ反映できませんでした。',
    DebtFailureKind.unknown => 'Debtを読み込めませんでした。',
  };
}
