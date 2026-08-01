# ADR 0012: 共有Firebaseデモの通知を認証済み独立APIへ委譲する

- Status: Accepted
- Date: 2026-08-01

## Context

複数EmulatorでDebt作成・救済・完済を通知するには、FCM送信権限とgroup単位の宛先解決が必要である。service accountをclientへ配布したり、clientにtoken・uid・文面を指定させることはできない。

## Decision

- Flutterは本人のFCM tokenを`users/{uid}/devices/{deviceId}`へ登録する。
- Debt / ContributionのFirestore transactionを変更せず、成功後にIDだけを通知APIへbest-effort送信する。
- FastAPIはFirebase ID Token、対象document、group membershipを検証し、Firestoreから有効端末を解決する。
- `eventType + sourceId`の決定的hashを`notificationEvents`へ予約し、再試行の重複送信を抑止する。
- Android通知は高重要度チャンネル`michizure_alerts_v1`へ統一し、`eventType`、`debtId`、`contributionId`、`sourceId`を遷移用dataとして送る。
- foregroundだけFlutter側でローカル通知を表示し、background／terminatedはFCMのシステム通知を使用する。通知タップは認証状態の復元後に対象Debtへ一度だけ遷移する。
- Docker imageはRenderで動かし、同じimageをAWS App Runnerへ移せるようportとSecretを環境注入する。

## Consequences

- 通知API障害はDebt / Contributionの成否へ影響しない。
- API予約後・FCM送信前のprocess停止では通知が欠落し得る。これはデモ向けの最低限の冪等性として受容し、厳密なdeliveryにはoutbox / leaseが必要である。
- service accountとFCM tokenは秘密情報としてlogやGitへ残さない。
