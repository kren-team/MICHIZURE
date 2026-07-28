# NEXT TASK: Phase 5 `feature/android-task-monitor`

## この1 Phaseだけを実装する

Android Foreground Serviceと`UsageStatsManager`を使い、実行中Taskからユーザー操作で離脱したことを誤判定防止filter付きで検知する。typedなnative eventをFlutter Application層へ渡し、Phase 4の冪等failure transactionへ接続する。

`DevicePolicyManager.setPackagesSuspended()`、lock obligation、Debt返済UI、CameraX、ML Kit、スクワット判定は実装しない。Phase 5で外部アプリを検知しても実際のpackage suspensionはPhase 6の責務とする。

## Branch

```text
feature/android-task-monitor
```

最新のcleanな`dev`から作成し、統合先は`dev`とする。`main` / `dev`へ直接機能commitしない。

## 作業前に読む

1. `AGENTS.md`
2. `README.md`
3. `docs/product-requirements.md`
4. `docs/architecture.md`
5. `docs/data-model.md`
6. `docs/android-enforcement.md`
7. `docs/firestore-rules-design.md`
8. `docs/state-management.md`
9. `docs/security-privacy.md`
10. `docs/testing.md`
11. `docs/demo-plan.md`
12. `docs/implementation-plan.md`
13. `docs/adr/0003-android-app-enforcement.md`
14. Phase 3/4のnative bridge、Task repository、controller、Rules、test

## Phase 4から引き継ぐ契約

- Firestore Taskは`running / succeeded / failed`、1ユーザー1 active pointer。
- `expectedEndAt`とFirestore `request.time`がterminal競合の権威。
- `failTaskAndCreateDebt`は`failureEventId`で冪等化し、same-ID Debtをatomic作成する。
- Phase 4 Rulesがclient writeを許可するfailure reasonは`user_aborted`だけ。Phase 5 reasonを開放する際は、native eventのshapeとTask/Debt after-stateを独立したRules testで追加する。
- Phase 3の`device_control/v1`契約とDataStore選択packageを壊さない。
- package名をFirestore、analytics、Production logへ送らない。

## 実装範囲

### Kotlin

```text
android/app/src/main/kotlin/com/kren/michizure/monitoring/
android/app/src/main/kotlin/com/kren/michizure/persistence/NativeTaskStore.kt
android/app/src/main/kotlin/com/kren/michizure/platform/TaskEventStreamHandler.kt
android/app/src/test/
android/app/src/androidTest/
```

- `TaskGuardService` foreground service
- `UsageEvents.Event.ACTIVITY_RESUMED`を使うforeground transition source
- own app / foreign app / launcher / Settings / permission controller / default dialer等を分類する純粋classifier
- screen non-interactive、Keyguard、許可済みsystem flow、通話中を考慮するinterruption gate
- foreign candidateのdwellとown app復帰時cancel
- native monotonic clockを使うdeadline競合
- process recreationに耐える最小Task recordとterminal compare-and-set
- version 1 EventChannel、再購読、同一terminal event ID再送
- capability喪失をtyped event / errorとして通知

### Flutter

```text
lib/features/task/infrastructure/native_task_guard.dart
lib/features/task/application/handle_native_task_event.dart
lib/features/task/presentation/
```

- WidgetからEventChannelを直接購読しない。
- Infrastructure adapterでpayloadを厳密に検証しDomain eventへ変換する。
- Application handlerがdeadlineと現在Task stateを再確認してsuccess / failureを選ぶ。
- duplicate eventはPhase 4 repositoryの同一event no-opへ収束させる。
- Running画面にguard health、capability lost、再試行可能なtyped failureを表示する。

### Firestore

- collection / field schemaは原則変更しない。
- Phase 5で必要な`foreign_app_foreground`、`monitor_capability_lost`、`recovery_detected_violation`だけを最小限開放する。
- Task、user pointer、same-ID Debtのatomic invariantを維持する。
- package名、installed app inventory、raw UsageEventを保存しない。

## 必須動作

- own appのActivity transitionでは失敗しない。
- interactive中にHome、Recents、foreign appへ移動し、dwellを超えた場合は1回だけfailure eventを生成する。
- foreign appからdwell内に戻ればcandidateをcancelする。
- screen off、Keyguard表示ではfailureにしない。
- permission/settings flowは明示的・短時間のleaseがある場合だけ除外し、無制限allowlistにしない。
- default dialerは実際の通話状態が確認できる場合だけpauseする。
- Usage Access喪失、service停止・復元をtypedに扱う。
- deadlineとforeign eventが競合した場合は、設計済み時刻policyに従い二重terminalを作らない。
- process / Activity再生成後もhandlerやlistenerを二重登録しない。

## Android permission / manifest

Foreground Service type、notification、Usage Statsに必要なpermissionだけを追加する。追加ごとに用途、runtime flow、API level差、Device Owner条件、Google Play policy、testを文書化する。AccessibilityService、Camera permission、`QUERY_ALL_PACKAGES`のrelease拡張は追加しない。

## Acceptance Criteria

- managed Android EmulatorでTask start後にguard notificationが表示される。
- Demo foreign app / Home遷移を1秒以内目標で1回のfailureへ変換できる。
- screen off / Keyguard / own Activity再開はfailureにならない。
- Usage Accessをrevokeしてもcrashせずcapability failureになる。
- duplicate native eventでTask / Debtが重複しない。
- deadline競合でTask terminal stateが1つに収束する。
- process再起動後にnative Task recordとFirestore Taskを照合できる。
- package名やraw UsageEventがPlatform payload、Firestore、Production logへ出ない。
- Phase 3のDevice Setup / App SelectionとPhase 4のTask flowが回帰しない。
- Flutter、Rules、Kotlin JVM、managed Emulator instrumentation、debug APK buildが成功する。

## 必須テスト

- classifier table: own / Home / Recents / foreign / Settings / permission controller / dialer
- interactive、screen off、Keyguard、system lease、call state
- dwell cancel、duplicate UsageEvent、out-of-order event
- event before Task start、deadline直前、deadline以後
- Usage Access revoke、service restart、Activity recreation
- EventChannel contract version、malformed payload、再購読、duplicate terminal event
- native event handlerのsingle-flight / idempotency
- Phase 5 failure reasonのRules allow / deny
- same-ID Debtとactive pointerのtransaction integration
- manifest permissionとrelease/debug差分

実時間sleepに依存するclassifier testは作らず、virtual monotonic clockを注入する。Device Owner / Usage Accessが必要な動作だけをmanaged Emulator instrumentation laneへ分離する。

## 推奨commit分割

1. `feat: Task Guard foreground serviceと永続recordを追加`
2. `feat: UsageEvents監視とforeground classifierを実装`
3. `feat: system interruption filterとdeadline競合を実装`
4. `feat: native Task eventをFlutter failure処理へ接続`
5. `test: Task monitorの誤判定と復元を検証`
6. `docs: Task monitor契約とデモ手順を更新`

Phase 5完了後は停止する。Phase 6のpackage suspension、lock obligation、unlockを先取りしない。
