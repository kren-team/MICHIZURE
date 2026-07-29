# NEXT TASK: Phase 6 `feature/android-app-lock`

## この1 Phaseだけを実装する

Phase 5のTask failure terminalを受け、Phase 3でTask開始時にsnapshotしたpackageをDevice Owner APIで封印する。Debtごとのlocal lock obligation、複数Debtのeffective union、完済または期限到達時の差分解除を実装する。

Debt返済UI / realtime Contribution、CameraX、ML Kit、スクワット判定、総合recovery polishは実装しない。

## Branch

```text
feature/android-app-lock
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
14. Phase 3のpackage catalog / selectionとPhase 5のTask Guard / native outbox

## Phase 5から引き継ぐ契約

- terminal eventはnative DataStoreへ先に保存され、同一`eventId`でFirestore ackまで再配送される。
- failure event payloadにpackage名は含めない。
- `NativeTaskRecord.lockTargetsAtStart`がそのTaskの封印対象snapshotである。
- `failTaskAndCreateDebt`はsame-ID Debtをatomic作成し、duplicate eventをno-opへ収束させる。
- `setPackagesSuspended()`はまだ一度も呼ばれていない。
- Task Guard serviceはterminal確定後に停止するため、lock deadline監視は独立して復元可能にする。

## 実装範囲

### Kotlin

```text
android/app/src/main/kotlin/com/kren/michizure/enforcement/
android/app/src/main/kotlin/com/kren/michizure/persistence/LockObligationStore.kt
android/app/src/main/kotlin/com/kren/michizure/platform/
android/app/src/test/
android/app/src/androidTest/
```

- `PackageSuspender`: `DevicePolicyManager.setPackagesSuspended()`の薄いadapter
- DPMが返すfailed package配列を最終authorityとして扱う
- failure event確定時にTask snapshotからDebt別obligationをlocalへ冪等作成
- unresolved obligationのpackage unionからapply / release差分を導出
- MICHIZUREが実際にsuspendできたowned packageだけを追跡
- 完済または期限到達時にunionを再計算し、他Debtが必要とするpackageを解除しない
- elapsed deadlineとwall/boot identityを保存し、process recreation後に再schedule
- partial failure、Device Owner喪失、package uninstallをtyped stateへ変換
- duplicate apply / releaseを安全なno-opにする

### Flutter

```text
lib/features/enforcement/application/
lib/features/enforcement/domain/
lib/features/enforcement/infrastructure/
lib/features/enforcement/presentation/
```

- Phase 5 terminal処理とlock obligation開始をApplication境界で接続
- Lock StatusにDebt別期限、effective target件数、enforced / degraded状態を表示
- manual reconcileをsingle-flightで提供
- WidgetからMethodChannel / DPMを直接呼ばない
- package名は端末内UI以外へ送らない

### Firestore

- Phase 6では原則schemaを増やさず、既存Debt `status` / `lockExpiresAt`を購読する。
- failed userが自分のactive Debtを取得するqueryとindexが設計どおりか確認する。
- package名、owned suspension、partial failure detailをFirestoreへ保存しない。
- Rules変更が必要ならdefault denyと既存Task / Debt invariantを維持し、allow / deny testを同じcommit系列へ追加する。

## 必須不変条件

- OS封印より前にobligationをlocalへ永続化し、途中失敗でも再適用可能にする。
- `effectivePackages = unresolvedかつ期限内obligationのpackage union`。
- Debt A / Bが同packageを参照する場合、Aだけ完済してもBがactiveなら解除しない。
- MICHIZUREが所有していないsuspensionを解除しない。
- DPM partial failureを成功扱いしない。成功分と失敗分を別々に記録する。
- logout、Activity終了、Firebase error、EventChannel切断だけを理由に解除しない。
- offlineでもlocal deadline到達時は解除し、再接続後にremote状態へ収束させる。
- protected packageを新しい固定blacklistだけで判断せず、Phase 3 catalog再検査とDPM戻り値を使う。

## Android / permission

- Device Ownerでのみ`setPackagesSuspended()`を呼ぶ。
- AccessibilityService、Lock Task Mode、Camera permission、VPN方式を追加しない。
- exact alarm permissionをMVP必須にしない。
- broadcast receiver / worker / foreground serviceを追加する場合はexport、boot/user-unlocked、Android 16制約、Play policyを文書化してtestする。

## Privacy

- obligation内package snapshotはnative localだけに保存する。
- package名、installed inventory、DPM failed配列をFirestore、analytics、Production logへ送らない。
- local storeはbackup対象外を維持する。

## Acceptance Criteria

- managed EmulatorでTask failure後、選択したDemo appが起動不能になる。
- network offlineでもfailure直後にlocal封印が適用される。
- DPM partial failureがdegradedとして残り、成功packageだけをowned setへ入れる。
- Debt A / Bが同packageを参照しても一方の完済で早期解除しない。
- 全obligation完済または期限終了後にowned packageだけを解除する。
- process recreation後にobligationとOS stateをreconcileできる。
- duplicate failure / apply / releaseでobligationやDPM操作結果が壊れない。
- Device Owner喪失、protected/uninstalled packageでcrashしない。
- package名がFirestore / Platform event / Production logへ出ない。
- Phase 3〜5の機能とtestが回帰しない。

## 必須テスト

- `LockReconciler` pure unit: empty、single、overlap、complete、expire、partial、owned差分
- obligation store: create idempotency、process recreation、boot / wall / elapsed policy、corrupt state
- PackageSuspender adapter: success、failed package戻り値、exception、Device Owner喪失
- managed Emulator instrumentation: suspendでlaunch不可、unsuspendでlaunch可、protected package拒否
- 2 Debt同一packageの一方だけresolveしてもsuspend継続
- deadline offline解除
- uninstall / reinstall
- MethodChannel version / malformed payload / typed partial failure
- Flutter lock controller single-flight / retry / terminal listener
- Firestore query / Rulesを変更した場合の独立allow / deny
- release manifestとprivacy boundary

## 推奨commit分割

1. `feat: package suspension adapterを追加`
2. `feat: Debt別lock obligationを永続化`
3. `feat: lock unionと差分reconcileを実装`
4. `feat: deadline解除とLock Statusを追加`
5. `test: 複数DebtとDPM復元を検証`
6. `docs: App Lock運用とPhase 7引き継ぎを更新`

Phase 6完了後は停止する。Phase 7のDebt realtime / repaymentを先取りしない。
