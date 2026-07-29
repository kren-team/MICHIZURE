# MICHIZURE

約束した集中タスクからユーザー操作で離脱すると、選択したAndroidアプリを一時的に封印し、所属グループにスクワット負債を発生させるAndroid向けプロダクトです。グループは端末上のスクワット判定を使って共同返済します。

設計フェーズを完了し、Phase 0〜9でFirebase、Group、Task、Android離脱検知・封印、Debt realtime、冪等Contribution / Outbox、CameraX + ML Kit Pose Detectionを構築しました。Phase 10ではAuth、Task Guard、App Lock、Debt、Contribution Outboxをprocess death、boot、network再接続、package変更後に収束させるRecovery基盤を実装しました。次はPhase 11のデモ仕上げです。以降も `dev` から機能ブランチを作成し、[implementation-plan.md](docs/implementation-plan.md) の順序で進めます。

## 設計上の重要な結論

- ハッカソンMVPは、管理対象のAndroid Emulatorを Device Owner としてプロビジョニングする。
- 封印は Kotlin から `DevicePolicyManager.setPackagesSuspended` を使用する。
- タスク離脱検知は、Foreground Service が `UsageStatsManager` の `ACTIVITY_RESUMED` を監視し、画面OFF・Keyguard・既知のシステム割り込みを除外する。
- 一般ユーザー向けの通常権限アプリでは、任意の他アプリを強制的に封印できない。公開版は「Android Enterprise管理端末版」または「強制封印を持たないコンシューマー版」に分ける。
- UI、ユースケース、Firestore連携は Flutter / Dart、Device Owner、UsageStats、CameraX、ML Kit は Kotlin が担当する。
- バックエンドは Firebase Authentication と Cloud Firestore のクライアントSDKのみを必須とし、MVPは Spark Plan で動かす。
- スクワット映像は保存・外部送信せず、CameraX + ML Kit Pose Detection + 状態機械で端末内判定する。

## ドキュメント

最初に以下を順番に読んでください。

1. [プロダクト要件とMVPスコープ](docs/product-requirements.md)
2. [システムアーキテクチャ](docs/architecture.md)
3. [画面・状態遷移](docs/screen-flow.md)
4. [Firestoreデータモデル](docs/data-model.md)
5. [Firestore Rules設計](docs/firestore-rules-design.md)
6. [Android封印・離脱検知](docs/android-enforcement.md)
7. [スクワット判定](docs/squat-detection.md)
8. [Recovery / Reconciliation](docs/recovery-reconciliation.md)
9. [Flutter状態管理](docs/state-management.md)
10. [セキュリティとプライバシー](docs/security-privacy.md)
11. [テスト戦略](docs/testing.md)
12. [実装計画](docs/implementation-plan.md)
13. [Emulatorデモ計画](docs/demo-plan.md)
14. [コスト見積もり](docs/cost-estimation.md)
15. [次の1ブランチの作業](NEXT_TASK.md)

技術判断の理由は [ADR一覧](docs/adr/) にあります。後続Agentは作業前に [AGENTS.md](AGENTS.md) も必ず読んでください。

## ブランチ戦略

```text
main
└── dev
    ├── chore/*
    └── feature/*
```

- `main`: リリース可能な状態のみ
- `dev`: 機能ブランチの統合先
- `feature/*`: 機能実装
- `chore/*`: 環境構築・ドキュメント・保守

`main` と `dev` へ直接機能コミットを行いません。force pushと既存コミットの書き換えは禁止です。

## 実装開始時の予定構成

```text
lib/
  core/
  features/
    auth/
    group/
    task/
    enforcement/
    debt/
    squat/
android/app/src/main/kotlin/com/kren/michizure/
firebase/
test/
integration_test/
```

実際の生成対象と依存関係は [NEXT_TASK.md](NEXT_TASK.md) に限定してあります。

## Phase 0 ローカル起動

### 必要なツール

- Flutter 3.44.0 / Dart 3.12.0
- Android SDKとAPI 23以上のAndroid Emulator
- Node.js 22
- Java 21

live Firebase project、`google-services.json`、service accountは不要です。debug buildは固定のdemo project `demo-michizure`だけを使用します。

初回に依存を復元します。

```bash
flutter pub get
npm --prefix firebase/rules-tests ci
```

Terminal 1でAuth / Firestore Emulatorを起動します。

```bash
npm --prefix firebase/rules-tests run emulators:start
```

固定portはAuth `9099`、Firestore `8080`、Emulator UI `4000`です。Terminal 2でAndroid Emulatorへアプリを起動します。

```bash
flutter run
```

Android Emulatorからhost machineへは `10.0.2.2` で接続します。起動後に `Bootstrap OK`、`Firebase Emulator`、`demo-michizure` が表示されればbootstrap成功です。別のhostが必要なdebug環境では次のように上書きできます。

```bash
flutter run --dart-define=MICHIZURE_FIREBASE_EMULATOR_HOST=127.0.0.1
```

### 品質ゲート

Flutterのformat / analyze / test、Firestore Rules Test、追跡対象のsecret-like file検査を一括実行します。

```bash
./tool/check_all.sh
```

Firestore Rulesはdefault denyです。本人の `users/{uid}`、所属メンバーに限定したgroup/member操作、hash化招待を許可します。Task開始・成功・手動/native failureではTask、user pointer、same-ID Debtのafter-stateを検証し、foreground package名は保存しません。Rules testだけを実行する場合は次を使います。

```bash
npm --prefix firebase/rules-tests test
```

接続済みAndroid Emulator上で、独立した2つのFirebase Auth clientによるGroup統合フローを検証できます。

```bash
firebase emulators:exec \
  --project demo-michizure \
  --only auth,firestore \
  "flutter test integration_test/group_flow_test.dart -d emulator-5554"
```

Phase 3のAndroid bridge、launcher app catalog、DataStore選択復元だけを接続済みEmulatorで検証する場合は、Firebase Emulatorを必要としません。

```bash
flutter test integration_test/device_setup_flow_test.dart \
  -d emulator-5554 \
  --no-uninstall
```

Phase 4のTask start競合、active pointer、手動失敗とsame-ID Debtの冪等性は、Auth / Firestore Emulatorと接続済みAndroid Emulatorで検証します。

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

Phase 7の2 client Debt realtime（同一failed userの複数Debtを含む）は次で検証します。各clientはgroup scoped、deadline順、最大20件のlistenerを使用します。

```bash
firebase emulators:exec \
  --project demo-michizure \
  --only auth,firestore \
  "flutter test integration_test/debt_realtime_test.dart \
    -d emulator-5554 \
    --no-uninstall"
```

Phase 8の3 client同時Contribution、duplicate event、最終1 rep競合、member summary realtime、端末Outbox復元は次で検証します。

```bash
firebase emulators:exec \
  --project demo-michizure \
  --only auth,firestore \
  "flutter test integration_test/debt_contribution_test.dart \
    -d emulator-5554 \
    --no-uninstall"
```

Phase 9のスクワット判定は、CameraX / ML Kitを含むAndroidテストとFlutter契約テストで検証します。カメラframe・landmarkはDartやFirestoreへ渡しません。

```bash
cd android
./gradlew :app:testDebugUnitTest
./gradlew :app:connectedDebugAndroidTest
```

Device Ownerを含む初回セットアップは [demo-plan.md](docs/demo-plan.md#6-apk-installとdevice-owner-provisioning) を参照してください。Device Owner appは通常のアンインストール対象にできないため、端末テストでは`--no-uninstall`を使用します。

CIは同じcheckに加えてAndroid debug APKをbuildします。ローカルでAPKを検証するにはAndroid SDKを設定してから実行します。

```bash
flutter build apk --debug
```

### live構成の境界

non-debug buildはdemo projectへfallbackしません。次の4つの `--dart-define` が不足すると `MissingLiveFirebaseConfiguration` でfail-fastします。

- `MICHIZURE_FIREBASE_API_KEY`
- `MICHIZURE_FIREBASE_APP_ID`
- `MICHIZURE_FIREBASE_MESSAGING_SENDER_ID`
- `MICHIZURE_FIREBASE_PROJECT_ID`

live設定、`.env`実値、signing keyをrepositoryへcommitしないでください。Phase 0はrelease signingとlive Firebase接続を構成しません。

Rules test用のFirebase CLIはローカル・CI限定のdevDependencyです。現行CLIの推移依存に `npm audit` 警告がある場合、`npm audit fix --force` で無検証downgradeせず、Firebase CLI更新時にRules testとともに見直します。
