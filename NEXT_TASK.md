# NEXT TASK: Phase 4 `feature/task-session`

## この作業だけを実装する

ユーザーが内容と時間を指定してTask sessionを開始し、`expectedEndAt`をauthorityとしてcountdown・成功・手動中断による失敗・再起動復元を行う。Phase 0〜3のFirebase、認証、Profile、Group、Device Setup、選択package保存を前提にする。

UsageStatsによるforeign app自動検知、Foreground Service、実際のpackage suspension、Debt返済、CameraX、ML Kit、スクワット判定は実装しない。

## 作業開始

1. `AGENTS.md` と全設計文書を読む。
2. 特に `docs/product-requirements.md`、`docs/architecture.md`、`docs/data-model.md`、`docs/firestore-rules-design.md`、`docs/state-management.md`、`docs/testing.md`、`docs/implementation-plan.md` のPhase 4を確認する。
3. Phase 3が統合された最新のcleanな `dev` から `feature/task-session` を作る。

## 必須設計制約

- TaskのauthorityはFirestoreの`startedAt`、`durationSec`、`expectedEndAt`、`status`であり、UI Timerだけを信用しない。
- 1ユーザーにつきactive Taskは1つとし、`users/{uid}.activeTaskSessionId`とTask documentをatomicに更新する。
- Task開始前にPhase 3のcapabilityと選択packageをpreflightする。未準備なら安全に開始を止める。
- process再起動後は`expectedEndAt`から残時間を再計算する。
- offline時にTransaction成功を偽らない。Task startはonline必須としてtyped failureを返す。
- Phase 4ではforeign app自動検知を実装しない。手動中断だけを明示的なfailure pathとして扱う。
- 実際のDebt document生成範囲は`docs/implementation-plan.md`とRules設計に従う。後続の返済UIやapp lockを先取りしない。

## 実装対象

```text
lib/features/task/domain/
lib/features/task/application/
lib/features/task/infrastructure/
lib/features/task/presentation/
lib/features/debt/domain/debt.dart
lib/features/debt/domain/debt_repository.dart
firestore.rules
firestore.indexes.json
firebase/rules-tests/
test/features/task/
integration_test/
```

Android nativeはTask timing contractのinterfaceまでとし、UsageStats monitorやForeground Serviceは追加しない。

## UI

- Task Composer: 内容、実行時間
- Device Setup / selected app preflight結果
- Running Task: server-derived deadlineから計算した残時間
- 成功結果
- 手動中断確認と失敗結果
- 復元中、offline、Rules deny、競合のsafe typed message

## Firestore

- `taskSessions/{taskId}`
- `users/{uid}.activeTaskSessionId`
- 必要なminimal `debts/{taskId}` create
- start / success / manual failureのatomic invariant
- unknown field deny、owner限定read/write、immutable field保護
- task history queryに必要なindex

MVP trust boundaryとRulesで保証できる範囲を明記し、Cloud Functionsを必須依存にしない。

## 完了条件

- Task作成、開始、countdown、成功、手動失敗が動作する。
- 同一ユーザーの同時開始でもactive Taskが1つを超えない。
- app process再起動後にrunning Taskが復元される。
- `expectedEndAt`経過済みなら再起動後に成功へ収束する。
- 未準備capability、未選択package、offline、競合を安全に扱う。
- Task stateと`activeTaskSessionId`がTransaction / Rulesで矛盾しない。
- Flutter unit/widget、Rules、repository integration test、debug APK buildが成功する。

## 必須テスト

- valid / invalid task contentとduration
- concurrent startとsingle-flight
- start transactionの成功・deny・offline
- running → succeeded
- running → failed（manual abort）
- process restart recovery
- deadline経過後のrecovery
- active pointer保護とunknown field deny
- 他UID Taskのget/update/list deny
- Phase 3 preflight未達時の開始拒否

## 推奨commit分割

1. `feat: Task sessionドメインとFirestore repositoryを追加`
2. `feat: Task開始transactionとpreflightを実装`
3. `feat: countdownとTask状態遷移UIを追加`
4. `feat: Task再起動復元を実装`
5. `test: Task transactionとRules検証を追加`
6. `docs: Task sessionの実装境界を更新`

Phase 5以降を先取りしない。作業完了時はbranch、commit、Task state machine、Firestore / Rules / Index差分、復元方式、テスト結果、Phase 5へ残したAndroid monitor境界を報告する。
