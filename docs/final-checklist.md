# MICHIZURE デモ前最終チェック

## 1. Build / CI

- [ ] `git status --short`が意図した状態
- [ ] `./tool/check_all.sh`
- [ ] `flutter build apk --debug`
- [ ] `flutter build apk --release`（live設定なしでbuildのみ。実行時fail-fastを維持）
- [ ] `./android/gradlew -p tools/demo-target assembleDebug`
- [ ] GitHub Actionsがgreen
- [ ] debug / release APKのsizeを記録
- [ ] release APKに`pose_landmarker_lite.task`が1件だけ含まれる
- [ ] ML Kit Pose dependencyがrelease dependency graphにない

## 2. Host / Firebase

- [ ] Auth Emulator `127.0.0.1:9099`
- [ ] Firestore Emulator `127.0.0.1:8080`
- [ ] Emulator UI `127.0.0.1:4000`
- [ ] project IDが`demo-michizure`
- [ ] service account、live credential、固定passwordをrepository / logへ出していない

## 3. Android A / B

- [ ] A/Bが`adb devices -l`でonline
- [ ] MICHIZURE debug APKを`install -r`済み（uninstall / data clearしない）
- [ ] Device OwnerがMICHIZURE
- [ ] Usage Access Ready
- [ ] Notification Ready
- [ ] user unlocked
- [ ] BのCamera permission
- [ ] Aへ`MICHIZURE Demo Target`をinstall
- [ ] App Selection候補にDemo Targetのlabelが表示される
- [ ] Aのdemo targetが開始時点でunsuspended
- [ ] `tool/demo_preflight.sh`がA/Bで成功

## 4. App state

- [ ] A/BのAuth userをUIで確認
- [ ] A/Bが同一Group、member 2人
- [ ] Aで封印対象1件（Demo Target）をcheckbox選択して保存
- [ ] App Selection / Home / Device Setup / Task Composerが同じ選択件数・labelを表示
- [ ] active Taskなし
- [ ] 既存active Debt / lock obligationを確認し、無視して削除していない
- [ ] Recoveryがhealthy。degradedなら原因を解消

## 5. Scenario A — 成功

- [ ] Aで1分の約束を開始
- [ ] Foreground Service通知とcountdown
- [ ] MICHIZURE内に留まる
- [ ] `succeeded`
- [ ] Demo Targetはunsuspendedのまま

## 6. Scenario B — 失敗・封印

- [ ] Aで約束を開始
- [ ] Demo Targetへ移動し600ms以上滞在
- [ ] Aの約束が`failed`
- [ ] same-ID Debtが1件、member数×10回
- [ ] Demo Targetがsuspendedで起動不能
- [ ] toolbar Homeまたは`adb shell input keyevent KEYCODE_HOME`でLauncherへ戻れる
- [ ] Bへ負債がrealtime表示
- [ ] screen off / notification shadeだけでは誤failureしない

## 7. Scenario C — 返済・解除

- [ ] Bで対象負債を明示選択
- [ ] `webcam0`をfrontへ割り当ててCamera previewを確認
- [ ] 胸の下〜足首guide、斜め30〜45度または横向きの案内
- [ ] PreviewとNative guideが同じportrait 3:4 bounds内
- [ ] debug diagnosticsでpose / side / confidence / feature / reject reasonを確認
- [ ] EmulatorはCPU固定。物理端末はGPUまたはCPU fallbackとして1回だけ確定
- [ ] analyzer / submit / callbackが増加し、inference latencyが0ms固定ではない
- [ ] callback待機とcallbackあり・poseなしが別表示
- [ ] debug既知画像でcallback、pose 1件以上、hip/knee/ankleを確認
- [ ] diagnosticsが4 FPS以下、analysisが物理GPU 12 FPS / 物理CPU 8 FPS / Emulator CPU 5〜6 FPS近傍
- [ ] 2秒・6〜8 valid sampleで直立calibration
- [ ] 前後phase、transition / reject / reset reason、frame dt、confirmation時間を記録
- [ ] 正常3 squatをexactly 3回count
- [ ] 深いsquat 1回をexactly 1回count
- [ ] 浅い屈伸3回を0回としてreject
- [ ] 複数squatで二重countなし
- [ ] pending / confirmedを区別
- [ ] 最終repでDebt completed
- [ ] Aのobligation release
- [ ] Demo Targetがunsuspendedで起動可能

## 8. Recovery

- [ ] running Taskで通常process kill→再起動→countdown / monitor復元
- [ ] active Lockでprocess kill→再起動→封印 / UI復元
- [ ] `adb reboot`後もDevice Owner維持
- [ ] reboot後unlockでlock / Taskが収束
- [ ] offline→onlineでnative event / Contributionがstable IDで1回だけ反映
- [ ] `am force-stop`は明示起動後reconcileとして別記録

## 9. Camera latency / resources

- [ ] 測定端末とCamera設定を記録
- [ ] analysis FPS、drop / busy、result / no-pose数を記録
- [ ] inference p50 / p95、native pipeline p50 / p95を記録
- [ ] 物理端末ではinference p95 100ms、native pipeline p95 180ms、rep表示p95 400msを目標とし、未達なら理由を記録
- [ ] Emulator値と物理端末値を分けて記録
- [ ] 返済画面離脱後にcamera privacy indicatorが消える
- [ ] Task terminal後にForeground Service通知が消える
- [ ] logcatにFATAL / unhandled / SecurityException / ImageProxy leakなし

## 10. Safe reset（wipe / uninstall禁止）

1. terminal Taskまで完了させる。
2. active Debtは正規Contributionまたは期限でterminalへ収束させる。
3. Lock Statusでactive obligation 0とunsuspendを確認する。
4. logout / loginする。local lock stateはlogoutだけで削除しない。
5. 必要なら新しいGroup、招待、Taskを通常UIから作る。
6. 封印対象はApp Selectionから変更して保存する。

active Debt、obligation、Firestore document、DataStoreを強制削除するresetは使用しない。

## 11. Go / No-Go

- [ ] Scenario A/B/Cが通る
- [ ] process kill、可能ならrebootが通る
- [ ] 実カメラ確認とlatency記録済み
- [ ] Security Rules 103件、Flutter、Kotlin、instrumentationがgreen
- [ ] debug / release manifestに`QUERY_ALL_PACKAGES`なし
- [ ] release manifestにcleartext / fake sourceなし
- [ ] Camera / pose / package inventory / Usage historyが端末外へ出ていない
