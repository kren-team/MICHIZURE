# テスト戦略

## 1. Quality gate

機能branchをdevへ統合する最低条件:

1. 対象Domain / Application unit test成功
2. 対象Widget test成功
3. Firestore schema / Rules変更があればRules Test成功
4. Kotlin変更があればJVM unit test成功
5. DPC / Camera / Platform Channel変更があれば対象instrumentation test成功
6. format / analyze / lint成功
7. 既存回帰test成功
8. privacy禁止事項を含むlog / file / dependencyがない

Device Ownerやcameraが必要なtestを一般unit testへ混ぜず、CI laneを分離する。

## 2. Test pyramid

| Layer | Tool候補 | 対象 |
|---|---|---|
| Dart unit | `flutter_test` | Entity、UseCase、Repository contract、Clock |
| Kotlin unit | JUnit / coroutine test | classifier、lock union、squat FSM |
| Firestore Rules | Emulator + `@firebase/rules-unit-testing` | auth、membership、atomic invariants |
| Widget | `flutter_test` + provider override | validation、state rendering、navigation |
| Repository integration | Flutter integration_test + Firebase Emulator | converter、transaction、listener、offline |
| Android instrumentation | AndroidX Test / managed emulator | DPM、FGS、UsageStats adapter、Camera lifecycle |
| End-to-end | 2 Android Emulators | failure→Debt→rep→unlock |
| Performance | instrumented debug/profile build | p95 transaction、sync、pose |

外部Firebase live projectを通常CIで使用しない。Rules Testと統合testは`demo-*` project IDのLocal Emulator Suiteを標準にする。

## 3. Domain / Application unit test

### User / Group

- displayName、group name、invite token validation
- userは1 groupだけ
- member count max 40
- ownerは移譲前にleave不可
- active Task中 / unresolved own Debt中のleave不可

### Task

- duration 60〜10,800秒
- `expectedEndAt = startedAt + durationSec`
- remaining timeの導出
- running→succeeded
- running→failed
- terminal→別terminal拒否
- deadline直前foreign eventはfailed
- deadline以降eventはsucceeded
- UI Timer遅延がterminal判定を変えない
- native failure eventの再送が冪等

### Debt

- `totalReps = memberCountAtFailure × 10`
- 1, 5, 40人で10, 50, 400 reps
- `remaining = max(0, total - completed)`
- active→completed / expired
- terminal state immutable
- 複数Debtのうち1件完済しても他obligationが残ればlock継続

### Contribution

- deterministic event ID
- ack 0 / 1のUI反映
- pendingとconfirmedを区別
- cached remaining以上のoffline検出をpause
- expired / completed Debtへのeventをdiscard

### Recovery

- localなし / remoteなし
- local running + remote running
- local running + remote terminal
- local pending failure + remote running
- local pending failure + remote既処理
- offline→online outbox flush
- wall clock jump / boot count change

fake `Clock`, `IdGenerator`, repositories, device adapterをprovider overrideし、sleepや実時刻に依存しない。

## 4. Kotlin unit test

### ForegroundTransitionClassifier

table-driven test:

| Scenario | Expected |
|---|---|
| own Activity resumed | ignore / candidate cancel |
| launcher resumed while interactive | failure after dwell |
| foreign app resumed | failure after dwell |
| screen non-interactive | ignore |
| keyguard locked | ignore |
| permission controller + valid lease | ignore |
| permission controller leaseなし | failure |
| default dialer + active call | pause |
| default dialer call state不明 | failure |
| foreign→own within 500ms | cancel |
| foreign remains >600ms | failure |
| duplicate UsageEvent | one candidate |
| Usage Access lost | capability failure |
| event before Task start | ignore |
| event at/after deadline | success wins |

virtual monotonic clockを使用する。

### LockReconciler

- obligation 0 → effective empty
- Aだけ → A packages apply
- A/Bが同package → refcount 2
- A完済、B active → package維持
- A/B完済 → release
- A期限切れ、B active →維持
- partial apply / releaseをdegradedとして保持
- protected packageをapplyしない
- uninstall / reinstall
- boot change後のdeadline
- logoutでobligationを消さない
- ownedでないsuspensionを解除しない

### Squat state machine

- normal rep exact 1
- 100 reps exact 100
- shallow bounce 0
- bottom bounce double countなし
- start at bottom 0
- 500ms movement 0
- 7秒movement 0
- confidence loss 100msなら継続、300msなら破棄
- threshold jitter
- left/right switch
- frame timestamp gap
- out-of-order sample
- count後refractory
- calibration failure / recovery

cameraやML KitをJVM unitへ持ち込まず、`PoseFeatureSample`を入力する純粋FSMにする。

## 5. Firestore Rules Test

Node test packageを`firebase/rules-tests/`へ置き、testごとにEmulator dataをclearして複数auth contextを作る。

### Fixtures

```text
alice: group owner / failed user
bob: member / contributor
carol: outsider
group5: 5 members
group40: 40 members
runningTaskAlice
activeDebt50
activeDebtAt49
expiredByClockDebt
```

### Authorization

- unauthenticated全拒否
- profile本人のみ
- group memberだけgroup / members / debt read
- outsider debt query拒否
- invite get許可、list拒否
- unknown field拒否
- update/delete禁止event

### Atomic invariant

- group create 3 docs atomic
- join user/member/count atomic
- 41人目拒否
- 2 group目拒否
- Task create + user pointer
- success + pointer clear
- failure + pointer clear + same-ID Debt
- Debt量formula
- rep event + summary + Debtを3 write atomic
- いずれか1 write欠落を拒否
- completedReps超過拒否
- deadline以降rep拒否
- deadline前expire拒否
- terminal rewrite拒否

### Rules access limits

- transactionが各operation 10、全体20 document access callsを超えない
- rule coverage reportでallow / deny branchを確認
- indexを要求するapp queryがRulesと一致

## 6. Concurrency test

Firestore Emulatorまたは専用test projectで、独立client contextを並列実行する。

### Debt cap

初期 `totalReps=50`, `completedReps=49` に20 clientから異なるeventを同時送信する。

期待:

- 最終 `completedReps == 50`
- status completed
- accepted eventは1件だけ
- summary合計は1だけ増える
- transaction retry / rejected結果がtypedに返る

### Full debt

5 clientが各10 eventsをconcurrent送信する。

- final 50
- event ID重複なし
- summary合計 = Debt completed
- Rules denied / transaction abortedを適切にretry

### Max group

40 client × 10 repsをtempoを模した間隔で送信し、contention、p95、error率を測る。無料quotaに影響するため通常はEmulatorで行う。

## 7. Repository integration test

- Firestore converter round-trip
- server timestamp resolution
- Task start / terminal transaction
- failure retry idempotency
- listener initial snapshot / update / detach
- cache snapshotとserver snapshotの区別
- network disable→outbox→enable→flush
- Debt expiration claim
- query limit / order / pagination
- Auth Emulator register/login/logout
- project ID guardがliveへの誤接続を止める

Emulator offline cacheはtest間でclearし、前回runを読まない。

## 8. Widget test

| Screen | Key assertions |
|---|---|
| Login / Register | validation、loading、typed error |
| Group Onboarding | create/join分岐 |
| Group Dashboard | member 5/40、active debts、offline badge |
| Device Setup | capabilityごとの説明と導線 |
| App Selection | protected app選択不可 |
| Task Composer | duration/content validation |
| Running Task | remaining、guard health、abort confirmation |
| Task Result | successはDebtなし、failureはDebt表示 |
| Debt Detail | remaining、member summary、terminal |
| Squat Counter | calibration、quality warning、detected/confirmed |
| Lock Status | 複数obligationと継続理由 |
| Recovery |各phase、degraded mode、retry |

golden image testはテーマ安定後のPhase 11で主要画面だけ追加する。

## 9. Android instrumentation

### Platform Channel contract

- contractVersion mismatch
- method success / typed error
- EventChannel再購読
- duplicate terminal event
- Activity recreationでhandler二重登録なし
- package名 / bitmapがpayloadに含まれない

### Device Owner lane

専用fresh managed emulator:

- isDeviceOwner true
- demo target suspendでlaunch不可
- unsuspendでlaunch可
- returned failed packageを処理
- protected package拒否
- 2 obligationsのunion
- process kill→launch→reconcile
- app update `adb install -r` 後reconcile
- boot後reconcile

Device Ownerでない一般emulator:

- setupへfail-fast
- DPM callを試行してcrashしない

### Task Guard lane

- FGS notification
- foreign demo target遷移
- Home、Recents
- screen off/on
- keyguard
- permission flow synthetic lease
- usage app-op revoke
- service restart

Phase 5では純粋classifierをJVM unitへ分離し、250msの実時間pollingを待たずにelapsed timestampを注入する。`NativeTaskStoreInstrumentationTest`はduplicate terminalの同一event ID、ack後の全消去、同一Task startの冪等性、異なるTaskとの競合、lock target snapshotを検証する。`TaskGuardManifestTest`はserviceが非exportかつ`systemExempted`であることをmanaged Emulator上で確認する。

Phase 6は`LockCoordinatorTest`でobligationのDPM適用前永続化、duplicate apply、partial failure、2 Debtのunion、期限解除、Device Owner喪失、process recreation / reinstall reconcileをpure fakeで検証する。`LockObligationStoreTest`はDataStore再生成後の復元、`AndroidPackageSuspenderTest`はmanaged Emulatorで選択可能packageのsuspend/unsuspendとself packageのfailed戻り値を検証し、`finally`で対象を必ず解除する。

標準command:

```bash
cd android
./gradlew :app:testDebugUnitTest
./gradlew :app:connectedDebugAndroidTest
```

実端末依存のHome / foreign app / screen offは下記の手動laneと分離し、classifier testをskipして代用しない。

### Camera lane

- permission grant/deny
- CameraX bind/unbind
- ImageProxy close
- synthetic landmark source
- real webcam smoke
- release buildでfake source不存在

## 10. Restart / recovery test matrix

| State at interruption | Action | Expected after launch |
|---|---|---|
| Task running | Activity recreate | countdown / guard継続 |
| Task running | process kill then manual launch | persisted Task評価、違反policy適用 |
| Task running | reboot | recovery policy、二重terminalなし |
| failure cloud未同期 | network off/on | lock継続、same Debt create |
| Debt active lock中 | app restart | suspension維持 |
| Debt completed while A background | listener receive | A unlock |
| Debt completed while A offline | reconnect | A unlock |
| Debt active deadline到達 | offline | local unlock、後でexpired |
| 2 Debts中A完済 | restart | B packagesは維持 |
| Contribution pending | process restart | event再送、duplicateなし |

`am force-stop` はユーザーによる強制停止でreceiver / serviceの挙動が通常killと異なる。両方を別ケースとして結果を記録し、MVP保証範囲を誇張しない。

## 11. End-to-end acceptance

2 Emulatorで次を自動または手動test:

1. A/B register
2. group作成 / join
3. A Task start
4. A foreign app
5. A failure + target suspend
6. B Debt snapshot 1秒以内
7. B synthetic/real squats
8. concurrent repでaggregate exact
9. Debt completed
10. A target unsuspend

test runはevent timestampsから同期p95を算出する。

Phase 2のGroupフローは、1台のAndroid Emulator内で2つの独立したFirebaseApp/Auth sessionを使う `integration_test/group_flow_test.dart` でも検証する。これはA/Bの認可境界とsnapshot listenerの反映を自動検証し、2台Emulatorによる画面操作smoke testを置き換えるものではない。

Phase 4はDart unit/widgetでcontent・duration・Clock・single-flight・routing・countdown・復元を検証し、`firebase/rules-tests/src/tasks_debt_creation.test.js`でTask/user/Debtのatomic invariant、owner query、terminal immutable、1/5/40人のDebt量を検証する。`integration_test/task_session_flow_test.dart`はAndroid上のFirebase SDKを使い、同時startが1件だけ成功すること、manual failureと同一event再送がsame-ID Debtへ収束することを確認する。

Phase 7はDebt converter、remaining/overdue導出、providerのgroup切替・logout・detach、一覧/detailのcache/empty/error/複数Debt、terminal snapshotからのnative releaseをDart testで検証する。`firebase/rules-tests/src/debt_lifecycle.test.js`はgroup/failed-user read境界、scoped query、期限前後のexpire、terminal immutable、Contribution write denyを独立して検証する。`integration_test/debt_realtime_test.dart`は2つのFirebaseApp/Auth clientで同一groupの初回追加と同一failed userの2 Debtを確認する。

```bash
firebase emulators:exec \
  --project demo-michizure \
  --only auth,firestore \
  "flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/task_session_flow_test.dart \
    -d emulator-5554 \
    --no-dds \
    --host-vmservice-port=51004"
```

Device Owner packageはtest終了時の自動uninstallをDPMが拒否する場合がある。test runnerが`All tests passed`かつexit code 0を返したことを合否とし、`DELETE_FAILED_DEVICE_POLICY_MANAGER`だけをtest failureと誤認しない。

## 12. Performance test

### Firestore

- operationごとのp50 / p95 / p99
- same region live projectでcold / warm
- writer ack→peer listener
- 5 / 40 concurrent contributors
- transaction retries / aborts

### Pose

- Camera timestamp→ML result
- ML result→FSM event
- EventChannel→UI render
- p95 500ms
- dropped frames / analyzer FPS
- Emulator + at least1 physical Android

### App monitor

- ACTIVITY_RESUMED→candidate
- candidate→failure
- poll CPU / battery proxy
- 250ms polling / 600ms dwellの実測

## 13. Privacy regression

CI/static review:

- camera/file write APIをpose packageで使用していない
- network clientをpose packageが依存していない
- Platform event fixtureにbitmap / landmarksなし
- package名をFirestore converterが受け付けない
- logsにemail、token、Task content、package、frameなし
- release manifestにdebug-only fake entryなし
- secret scanner / gitignore

## 14. Planned commands

Phase 0で実行可能にする。

```bash
flutter format --set-exit-if-changed .
flutter analyze
flutter test

cd firebase/rules-tests
npm test

cd android
./gradlew test
./gradlew connectedDebugAndroidTest

firebase emulators:exec --project demo-michizure \
  --only auth,firestore "flutter test integration_test"
```

実際のCIではworking directoryとemulator lifecycleをscript化し、shell commandをcopy-pasteで重複管理しない。
