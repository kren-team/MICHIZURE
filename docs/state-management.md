# Flutter状態管理設計

## 1. 採用方針

Riverpodを状態管理とDependency Injectionに使用し、次の3種類を区別する。

- Domain state: Task、Debt、Squat等の不変Entityと状態機械
- Application state: 複数Repositoryを調停する処理中・同期中・エラー
- Presentation state: 入力値、選択、表示用派生値

Firestore snapshotそのものをWidgetで購読しない。RepositoryがDomain streamへ変換し、Controller / Notifierが画面状態へ変換する。

## 2. Provider分類

| Provider | 用途 | 例 |
|---|---|---|
| plain `Provider` | Repository portへの実装注入 | `debtRepositoryProvider` |
| `StreamProvider` | 長寿命の外部stream | `authUserProvider`, `activeDebtsProvider` |
| `FutureProvider` | idempotentな一回取得 | `deviceCapabilitiesProvider` |
| `NotifierProvider` | 同期的UI状態 | Task入力、Debt選択 |
| `AsyncNotifierProvider` | commandと非同期状態 | login、createGroup、startTask |

Riverpod code generationはMVPで使用しない。build_runner依存と生成差分を減らし、必要性が生じた場合はADRを追加する。

## 3. 代表的な状態

```text
TaskComposerState
  content
  duration
  validationErrors
  submission: idle | checking | writing | startingGuard | done | error

RunningTaskViewState
  task
  remaining
  guardHealth
  syncState
  terminalEvent

DebtDetailViewState
  debt
  contributionByUser
  detectedReps
  confirmedReps
  pendingRepEvents
  detectorQuality

RecoveryState
  checkingLocal
  enforcingLocks
  restoringAuth
  flushingOutbox
  reconcilingRemote
  ready | degraded | fatal
```

`AsyncValue`だけで業務状態を表現しない。例えば「読み込み成功だがoffline cache」「ローカル検出済みだが未確定」は独立したfieldとして保持する。

## 4. Provider lifetime

- auth streamとRecoveryCoordinatorはapp scopeで維持する。
- user docはログイン中だけ維持する。
- group doc、members、active debtsはGroup dashboardが表示中、またはlock reconciliationが必要な間だけ維持する。
- Debt contributionsはDebt detail表示中だけ購読する。
- Camera / pose providerはSquat画面表示中だけ有効にする。
- `autoDispose`を標準とし、画面外でも必要なProviderだけ明示的にkeep aliveする。
- native Foreground ServiceをDart Providerのlifetimeだけに依存させない。

## 5. Router redirect

redirect判定の優先順位:

1. bootstrap未完了 → Splash / Recovery
2. 未認証 → Login / Register
3. profile未作成 → Profile Setup
4. running Taskあり → Running Task（設定画面など明示allowlistを除く）
5. group未所属 → Group Onboarding
6. capability未設定 → Device Setup
7. 通常Home

Debtによるロック中もMICHIZUREのGroup / Debt / Squat画面は利用できる。ロックは外部アプリに対するOS policyであり、アプリ内の全面ブロックrouteにはしない。

## 6. Repository ports

```text
AuthRepository
UserRepository
GroupRepository
TaskRepository
DebtRepository
DeviceControlRepository
SquatDetector
RecoveryStore
Clock
IdGenerator
```

テストでは以下をprovider overrideする。

- Firestore Repository → in-memory fake
- `DeviceControlRepository` → fake capabilities / lock events
- `SquatDetector` → synthetic detector
- `Clock` → fake clock
- `IdGenerator` → deterministic IDs

## 7. Error model

Infrastructure例外をPresentationへ直接投げない。最低限次のtyped failureへ正規化する。

```text
AuthFailure
PermissionFailure
ConflictFailure
OfflineFailure
RulesDeniedFailure
NativeCapabilityFailure
DetectorFailure
UnexpectedFailure(causeId)
```

ユーザー表示には復旧操作を添える。内部例外文字列、package名、Firebase token、stack traceをUIやanalyticsへ出さない。

## 8. Commandの冪等性

- button commandは実行中に再押下を拒否する。
- Task failureはnative `eventId` をkeyにoutboxへ保存する。
- Contributionは `squatSessionId_sequence` をevent IDにする。
- Group joinはtransactionで自分のmember doc不存在と `users.groupId == null` を確認する。
- command成功後にローカルstateを手動で推測せず、server ackまたはsnapshotへ収束させる。

## 9. 時刻

Domainへ`Clock`を注入し、次を分離する。

- `wallNow`: Firestore timestamp比較と再起動復元
- `elapsedNow`: 同一boot内のcountdown / dwell / squat動作時間
- `request.time`: Security Rulesの権威時刻

UI Timerは表示更新だけに使い、成功判定のsource of truthにしない。

`RunningTaskScreen`は1秒tickerを再描画triggerにだけ使用し、注入された`Clock.now()`とTaskの`expectedEndAt`からremainingを毎回導出する。Phase 5以降のterminal authorityはnative Task Guardであり、`deadlineReached`またはfailure eventを`TaskGuardController`がFirestore transactionへ接続する。process再起動時はAuth/Profile streamがactive pointerを復元し、globalなTask Guard event購読が未ack outboxを同一event IDで再処理する。Firestore commit後のnative ackだけがoutboxを削除する。

Phase 4のcommand stateは`TaskCommandController`がstart / success / manual abortを直列化する。Firestore transactionが1 active Task、terminal transition、Debt生成の本質的な整合性を担い、button disableはUX上の補助に留める。

Phase 5の`TaskGuardController`は`idle / starting / monitoring / synchronizing / retryNeeded / terminal`を持つ。native eventの同一IDをsingle-flight化し、offline / channel failureでは2秒後に同じeventをretryする。WidgetはEventChannelを直接購読せず、Running画面はcontroller stateからguard healthと安全なtyped errorだけを表示する。

## 10. 過剰設計を避ける基準

- CRUDを1回呼ぶだけならControllerからRepositoryを呼ぶ。
- 複数Repository、transaction、outbox、native commandをまたぐ場合だけUseCaseを作る。
- Entityごとに無条件でDTO / DAO / Mapperを三重化しない。Firestore converterとDomain Entityの2境界で開始する。
- service locatorを追加せずRiverpod provider graphへ統一する。
- Redux/BLoCとの併用をしない。
