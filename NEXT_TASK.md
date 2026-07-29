# NEXT TASK: Phase 7 `feature/debt-realtime`

## 目的

Phase 6で作成したsame-ID Debtをgroup内へリアルタイム表示し、failed user側ではDebt `completed` / `expired` を受けて既存の `releaseLockObligation(debtId)` 境界へ接続する。

このPhaseはDebtの購読・一覧・詳細・期限切れ収束とlock解除通知だけを扱う。Contribution書込、スクワット、Camera、ML Kitは実装しない。

## Branch

```bash
git fetch origin
git switch dev
git pull --ff-only origin dev
git switch -c feature/debt-realtime
```

## 最初に読む

1. `AGENTS.md`
2. `README.md`
3. `docs/architecture.md`
4. `docs/data-model.md`
5. `docs/firestore-rules-design.md`
6. `docs/android-enforcement.md`
7. `docs/state-management.md`
8. `docs/security-privacy.md`
9. `docs/testing.md`
10. `docs/implementation-plan.md`
11. `docs/adr/0002-firebase-backend.md`
12. `docs/adr/0003-android-app-enforcement.md`

## In scope

### Domain / Application

- active / completed / expired Debt状態とremaining reps表示
- group active Debt一覧（`lockExpiresAt asc`, `limit 20`）
- Debt詳細とmember contribution summaryのread-only表示
- failed userのactive obligation query
- overdue active Debtを`request.time`でexpiredへ収束するtransaction
- remote `completed` / `expired` をPhase 6の`releaseLockObligation`へ冪等接続
- listenerのattach / detachとtyped offline/error state

### Infrastructure

- `FirestoreDebtRepository`をquery/listener/expirationへ拡張
- converterのstrict field validationを維持
- `firestore.indexes.json`の既存active/history/failed-user indexを検証
- package名やnative suspension状態をFirestoreへ追加しない

### Presentation

- Group dashboardのactive Debt概要
- Debt List / Debt Detail
- remaining、failed member、期限、status、member別確定数
- cached/offline/error/retry表示
- failed userのLock Statusへremote解除結果を反映

### Firestore Rules

- group memberまたはfailed userだけDebt read
- group scoped queryを要求
- activeからexpiredへのdeadline後transitionだけを追加
- completed/expired terminal immutable
- contribution writeはPhase 8までdefault deny

## Out of scope

- Contribution Event / summary write
- completedReps加算
- concurrent repayment
- Squat Detection / Camera
- fake rep
- Cloud Functions
- Phase 8以降の先取り

## 必須不変条件

- Debt残数は`totalReps - completedReps`からO(1)で導出し、Contribution Eventsを集計しない。
- group queryは必ずcurrent `groupId`で制約し、Rulesをfilterとして扱わない。
- overdue表示だけでterminalとせず、transactionとRules `request.time`でexpiredへ収束する。
- remote terminalを受けても、Phase 6 reconcilerが他のactive obligationを参照しているpackageは解除しない。
- logout、listener error、cache missをunlock理由にしない。
- listenerを画面外でdetachし、無制限queryを作らない。

## Acceptance Criteria

- failure後、group member側のactive Debt一覧へrealtime反映される。
- Debt Listは最大20件、deadline順でありContribution Event全件を読まない。
- outsider / 他group userのDebt get/queryはRulesで拒否される。
- failed userは自分のDebtを必要最小限読める。
- deadline前expireは拒否、deadline後だけactive→expired可能。
- completed / expired Debtの再更新・deleteは拒否される。
- remote terminal受信で該当obligationをresolveし、他obligationが残るpackageは維持される。
- offline/cache状態と再接続後の収束をUIで区別する。
- Firestoreからpackage名、installed inventory、DPM結果を読み書きしない。

## Tests

- Debt converter valid / unknown field / invalid aggregate
- active queryのgroup scope / order / limit
- member / outsider / failed userのRules allow-deny
- deadline前後のexpiration transaction
- terminal immutable / delete deny
- listener initial/update/detach
- 2 client realtime反映
- remote completed / expired → native release
- 2 obligations中1件だけterminalでもlock継続
- typed offline / Rules denied / native release failure

## 推奨commit分割

1. `feat: Debt repositoryとactive queryを追加`
2. `feat: Debt一覧と詳細を実装`
3. `feat: Debt期限切れ収束を実装`
4. `feat: remote terminalをlock解除へ接続`
5. `test: Debt realtimeとRulesを検証`
6. `docs: Phase 7結果と次Phaseを更新`

## 停止条件

Phase 7完了後は停止する。Phase 8のContribution実装を開始しない。
