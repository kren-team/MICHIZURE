# Planned phases complete

Phase 0〜11の計画実装は完了した。新しいPhase 12は定義しない。

## 現在の状態

- Auth / Profile / Group / Task / Task Monitor / App Lockを実装済み
- Debt realtime / Contribution / CameraX + ML Kit squat detectionを実装済み
- process / boot / network / outbox recoveryを実装済み
- 状態別Home導線、端末setup案内、独立demo target、preflightを実装済み
- Firestore schema / Rules / IndexはPhase 11で変更なし
- debug shortcut、任意Debt / Contribution / unlock APIは追加していない

## Merge前の必須項目

1. `./tool/check_all.sh`
2. `./gradlew :app:testDebugUnitTest`
3. `./gradlew :app:connectedDebugAndroidTest`
4. `flutter build apk --debug`
5. `flutter build apk --release`
6. `./android/gradlew -p tools/demo-target assembleDebug`
7. [final-checklist.md](docs/final-checklist.md) に結果を記録

自動testまたはbuildが失敗している状態ではPhase 11完了としない。

## デモ前の必須手動確認

- 2台のmanaged Android EmulatorでScenario A（成功）
- Aのfailure→Debt→package suspend（Scenario B）
- Bの実カメラsquat→completed→Aのunsuspend（Scenario C）
- running Task / active Lockのprocess kill復元
- 可能ならOS reboot後のDevice Owner / lock復元
- 実カメラで浅い屈伸reject、二重countなし、local latency p50 / p95 / max
- logcatにアプリ固有のfatal、SecurityException、camera / service leakがない

環境上実施できない項目は成功とみなさず、デモ前のNo-Go項目として残す。

## 将来改善候補（未計画）

- Android Enterpriseとしての配布 / provisioning設計
- consumer版の強制封印なしUX
- App Check / attestation / trusted contribution backend
- physical device calibrationの母数拡大
- live Firebase、release signing、Play policy対応
- WCAGを含む完全なaccessibility監査

これらを着手する場合は、新たな要件合意とADRを先に作成する。
