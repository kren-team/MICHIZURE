# NEXT TASK: Phase 10 `feature/recovery-reconciliation`

## 目的

Phase 4〜9で実装したTask、native failure outbox、Debt、App Lock obligation、Contribution outboxを、Activity再生成、process death、reboot、network再接続後に同じstable IDへ安全に収束させる。

Phase 11のデモpolish、seed、画面の大規模な装飾は実装しない。

## Branch

```bash
git fetch origin
git switch dev
git pull --ff-only origin dev
git switch -c feature/recovery-reconciliation
```

## 最初に読む

1. `AGENTS.md`
2. `README.md`
3. `docs/architecture.md`
4. `docs/data-model.md`
5. `docs/android-enforcement.md`
6. `docs/state-management.md`
7. `docs/security-privacy.md`
8. `docs/testing.md`
9. `docs/implementation-plan.md`
10. 関連ADR

## In scope

- app bootstrap時の段階的`RecoveryCoordinator`
- running Taskとnative Task Guard contextの照合・復元
- pending terminal eventのsame-ID再送とFirestore ack後削除
- native lock obligationとDPM実状態のreconcile
- active / terminal Debtとlocal obligationの照合
- Contribution Outboxのauth user単位flush
- offline / reconnect、Activity recreation、process recreation、package replace、boot
- corrupted local stateのtyped degraded / fatal診断
- wall clock / elapsed clock / boot discontinuityの既存policy適用

## Out of scope

- Debt / Contribution schemaの再設計
- lock方式の変更
- Camera判定thresholdの再調整
- demo target、seed、golden、Phase 11 UI polish
- Cloud Functions必須化

## 必須不変条件

- stable task / debt / event IDを作り直さない。
- remote terminal Taskをrunningへ戻さない。
- pending eventはFirestore ackまたは正規terminal reject前に消さない。
- terminal Debt 1件だけを理由に、他のactive obligationが要求するpackageを解除しない。
- logoutやFirebase errorだけを理由にunsuspendしない。
- Camera frame、package inventory、UsageEventsをrecovery payloadへ追加しない。
- Firestoreを高頻度pollingしない。

## Acceptance Criteria

- running TaskがActivity / process再生成後にcountdownとTask Guardへ復元される。
- offline中のnative terminal eventが再接続後にsame-ID Task / Debtへ収束する。
- active lockがprocess / package replace / reboot後も維持される。
- offline中にterminal化したDebtが再接続後に正しくobligation解除へ収束する。
- pending Contributionが二重計上なしでflushされる。
- local state破損やcapability喪失をクラッシュではなくtyped diagnosticとして表示する。
- recovery matrixを自動テストし、force-stopと通常process killの保証差を報告する。

## Tests

- Dart RecoveryCoordinator unit / provider lifecycle
- Task / terminal outbox idempotency
- Contribution Outbox duplicate / auth switch
- Kotlin lock / Task context restoration
- Activity recreation / process kill / `adb install -r` / reboot
- network off→on
- clock / boot discontinuity
- Phase 1〜9回帰、Rules Test、Kotlin / instrumentation、debug APK build

## 停止条件

Phase 10完了後は停止する。Phase 11 `feature/demo-polish`は開始しない。
