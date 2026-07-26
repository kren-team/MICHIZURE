# NEXT TASK: Phase 3 `feature/device-setup-app-selection`

## この作業だけを実装する

Device Owner、Usage Access、notification、package visibilityの診断と、封印対象アプリの選択・端末内保存を実装する。Phase 0〜2のFirebase bootstrap、認証、プロフィール、Group機能を前提にする。

Task session、他アプリへの遷移監視、実際のpackage suspension、Debt、CameraX、ML Kit、スクワット判定は実装しない。

## 作業開始

1. `AGENTS.md` と全設計文書を読む。
2. 特に `docs/android-enforcement.md`、`docs/security-privacy.md`、`docs/state-management.md`、`docs/testing.md`、`docs/implementation-plan.md` のPhase 3、ADR 0003を確認する。
3. Phase 2が統合された最新のcleanな `dev` から `feature/device-setup-app-selection` を作る。

## 必須設計制約

- Android固有処理だけをKotlinに置き、FlutterとはtypedなPlatform Channel境界で接続する。
- Device Ownerはハッカソン用managed Emulator構成であり、一般ユーザー端末で利用可能と偽らない。
- package inventoryと選択package名はFirestoreや外部サービスへ送らず、端末内だけに保存する。
- debug/demo向けのbroad package visibilityとProduction配布方針を分離する。
- システム必須package、自アプリ、launcher、Settings等を選択・封印対象にしない。
- Phase 1のdebug限定cleartext許可をreleaseへ広げない。
- Method Channelの生例外をUIへ露出せず、typed capability/failureへ変換する。

## 実装対象

```text
lib/features/enforcement/domain/
lib/features/enforcement/application/
lib/features/enforcement/infrastructure/device_control_channel.dart
lib/features/enforcement/presentation/device_setup/
lib/features/enforcement/presentation/app_selection/
android/app/src/main/kotlin/com/kren/michizure/admin/
android/app/src/main/kotlin/com/kren/michizure/enforcement/PackageCatalog.kt
android/app/src/main/kotlin/com/kren/michizure/platform/
android/app/src/main/AndroidManifest.xml
android/app/src/main/res/xml/device_admin_receiver.xml
android/app/src/debug/AndroidManifest.xml
test/features/enforcement/
android/app/src/test/
```

Firestore変更はない。package selectionは既存設計で指定されたAndroidローカル永続化を使う。

## UI

- Device Setup checklist
- Device Owner / Usage Access / notification / package visibilityの状態と設定導線
- lock可能アプリ一覧と複数選択
- 選択の保存・復元
- managed demoと一般端末で利用できない機能の明示

## 完了条件

- Android EmulatorでDevice Owner capabilityを診断できる。
- lock対象として安全なpackageだけを列挙できる。
- package選択を保存し、アプリ再起動後に復元できる。
- package inventoryがnetwork/Firestoreへ送信されない。
- capabilityなし、権限拒否、Platform Channel失敗を安全なUIで表示できる。
- Flutter unit/widget test、Kotlin unit test、`flutter build apk --debug` が成功する。
- Device Owner provisioningを含むsmoke test手順がドキュメント化される。

## 推奨commit分割

1. `feat: Device Owner capability診断を追加`
2. `feat: lock可能アプリcatalogを実装`
3. `feat: app選択とローカル永続化を追加`
4. `test: device control channelとpackage制約を検証`
5. `docs: Device setupの実行手順を更新`

Phase 4以降を先取りしない。作業完了時はbranch、commit、Platform Channel contract、Android権限・manifest差分、ローカル保存方式、テスト結果、既知のmanaged-device制約を報告する。
