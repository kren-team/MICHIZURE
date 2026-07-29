# NEXT TASK: Phase 8 `feature/debt-contributions`

## 目的

Phase 7でrealtime表示できるactive Debtへ、Group memberが1 repずつ冪等にContributionを確定できるFirestore transactionとlocal outboxを追加する。

このPhaseはContribution Event / member summary / Debt aggregateの整合性、並行返済、offline retryだけを扱う。Camera、ML Kit、スクワット姿勢判定はPhase 9であり実装しない。

## Branch

```bash
git fetch origin
git switch dev
git pull --ff-only origin dev
git switch -c feature/debt-contributions
```

## 最初に読む

1. `AGENTS.md`
2. `README.md`
3. `docs/architecture.md`
4. `docs/data-model.md`
5. `docs/firestore-rules-design.md`
6. `docs/state-management.md`
7. `docs/security-privacy.md`
8. `docs/testing.md`
9. `docs/implementation-plan.md`
10. `docs/adr/0002-firebase-backend.md`

## In scope

### Domain / Application

- deterministic Contribution Event ID
- 1 event = 1 confirmed rep
- Debt、`contributions/{uid}`、`contributionEvents/{eventId}`のatomic transaction
- duplicate eventのno-op
- `completedReps <= totalReps`
- 最終repでactive→completed、`closedAt`設定
- terminal / expired Debtへのsubmit拒否
- local outbox、offline retry、ack、process restart復元
- detected / pending / confirmed / rejectedのtyped state

### Infrastructure

- `FirestoreContributionRepository`
- transactionは全read後にwrite
- Debt aggregateをContribution全件から再集計しない
- `lastContributionEventId`とsummary `lastEventId`のafter-state link
- contribution event / summary converterのstrict validation
- 必要なindex exemption

### Presentation

- Phase 7 Debt detailから「このDebtを返済する」導線
- Cameraを使わないdebug/手動rep生成をProductionへ追加しない
- pending / confirmed / offline / full Debtの表示
- member別summaryの既存realtime表示を更新

### Firestore Rules

- current group member本人だけが自分のevent / summaryを正規transactionでwrite
- event create-only、update/delete拒否
- summary単独write拒否
- Debt正確な+1、total cap、deadline、status transitionを`getAfter()`で検証
- Contribution Event全件を通常UI queryしない

## Out of scope

- Camera / CameraX
- ML Kit Pose Detection
- squat state machine
- fake pose / fake rep production route
- package suspension方式の変更
- Cloud Functions
- Phase 9以降の先取り

## 必須不変条件

- duplicate event IDはDebtもsummaryも二重加算しない。
- 49/50へ複数clientが同時submitしても最終値は50を超えない。
- Debt、summary、eventのいずれかが欠けるwriteはRulesで拒否する。
- offline中のrepはconfirmedとして表示せずoutboxへ保持する。
- terminal / deadline後のpending eventは再接続時に安全にreject/discardする。
- package名、画像、landmark、Task内容をContributionへ追加しない。

## Acceptance Criteria

- Group memberの正規eventでDebtと自分のsummaryが正確に1増える。
- 同一event retryは成功済みno-opとなる。
- concurrent submitでも`completedReps`が`totalReps`を超えない。
- 最終repだけがDebtをcompletedへ遷移させる。
- completed snapshotがPhase 7経由でfailed userのlock obligationを解除する。
- offline outboxが再接続後に順序送信され、duplicateを作らない。
- Contribution write以外のPhase 7 read境界とdefault denyを維持する。

## Tests

- event ID / converter / typed result unit
- duplicate event
- missing Debt / summary / event write deny
- 49/50へ20 concurrent clients
- 5人Debt 50 repsのaggregate / summary整合
- deadline / completion race
- terminal / outsider / other-group deny
- offline outbox retry / process restoration
- completed Debt→Phase 7 release integration
- 既存Phase 1〜7回帰

## 推奨commit分割

1. `feat: Contribution eventとsummary modelを追加`
2. `feat: idempotent rep transactionを実装`
3. `feat: Contribution outboxを追加`
4. `feat: Debt返済状態をUIへ接続`
5. `test: Contribution並行更新とRulesを検証`
6. `docs: Phase 8結果と次Phaseを更新`

## 停止条件

Phase 8完了後は停止する。Phase 9のCamera / Squat Detectionを開始しない。
