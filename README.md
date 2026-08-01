# MICHIZURE

約束した集中タスクからユーザー操作で離脱すると、選択したAndroidアプリを一時的に封印し、所属グループにスクワット負債を発生させるAndroid向けプロダクトです。グループは端末上のスクワット判定を使って共同返済します。

計画したPhase 0〜11を実装済みです。Firebase、Group、Task、Android離脱検知・封印、Debt realtime、冪等Contribution / Outbox、CameraX + MediaPipe Pose Landmarker Lite、Recovery基盤を、managed Android Emulatorで説明可能なデモ導線へ統合しています。デモ前の確認は [final-checklist.md](docs/final-checklist.md) に従ってください。

## 設計上の重要な結論

- ハッカソンMVPは、管理対象のAndroid Emulatorを Device Owner としてプロビジョニングするんご。
- 封印は Kotlin から `DevicePolicyManager.setPackagesSuspended` を使用する。
- タスク離脱検知は、Foreground Service が `UsageStatsManager` の `ACTIVITY_RESUMED` を監視し、画面OFF・Keyguard・既知のシステム割り込みを除外する。
- 一般ユーザー向けの通常権限アプリでは、任意の他アプリを強制的に封印できない。公開版は「Android Enterprise管理端末版」または「強制封印を持たないコンシューマー版」に分ける。
- UI、ユースケース、Firestore連携は Flutter / Dart、Device Owner、UsageStats、CameraX、MediaPipe は Kotlin が担当する。
- バックエンドは Firebase Authentication と Cloud Firestore のクライアントSDKのみを必須とし、MVPは Spark Plan で動かす。
- 共有Firebaseデモの通知だけは、Firebase ID Tokenを検証する独立FastAPIからFCMへ送信する。
- スクワット映像は保存・外部送信せず、CameraX + MediaPipe Pose Landmarker Lite + One-Euro Filter + 状態機械で端末内判定する。
- 封印候補は`LauncherApps`からLauncher起動可能appだけを取得し、debug / releaseとも`QUERY_ALL_PACKAGES`を使用しない。
- スクワットは左右いずれか同じ側のhip / kneeを入力とし、顔・肩・足首を判定必須にしない。Previewとguideはnativeの同一3:4 containerへ配置する。実Camera成立率とlatencyはデモ前manual gateで確認する。

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
16. [デモ前最終チェック](docs/final-checklist.md)

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

## 実装構成

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

`tools/demo-target/` は封印・解除を確実に見せる独立APKであり、MICHIZURE本体のrelease artifactには含まれません。

## ローカル起動

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

スクワット判定は、CameraX / MediaPipe adapter、model-independentな`LowerBodyPose`、pure Kotlin One-Euro Filter / 状態機械、Flutter契約テストで検証します。カメラframe・landmark座標はDartやFirestoreへ渡しません。

```bash
cd android
./gradlew :app:testDebugUnitTest
./gradlew :app:connectedDebugAndroidTest
```

Device Ownerを含む初回セットアップは [demo-plan.md](docs/demo-plan.md#6-apk-installとdevice-owner-provisioning) を参照してください。Device Owner appは通常のアンインストール対象にできないため、端末テストでは`--no-uninstall`を使用します。

デモ対象APKをbuildしてインストールします。

```bash
./android/gradlew -p tools/demo-target assembleDebug
adb -s emulator-5554 install -r \
  tools/demo-target/app/build/outputs/apk/debug/app-debug.apk
```

Firebase Emulatorと端末の読み取り専用preflightを実行します。選択アプリ、Auth、Group、active Task / Debtは最後にアプリ画面で確認します。

```bash
MICHIZURE_DEVICE_SERIAL=emulator-5554 ./tool/demo_preflight.sh
MICHIZURE_DEVICE_SERIAL=emulator-5556 \
  MICHIZURE_REQUIRE_CAMERA=1 ./tool/demo_preflight.sh
```

CIは同じcheckに加えてAndroid debug APKをbuildします。ローカルでAPKを検証するにはAndroid SDKを設定してから実行します。

```bash
flutter build apk --debug
```

release artifactはlive Firebase設定をrepositoryへ追加せずbuild検証できますが、実行時は下記4項目がなければ意図どおりfail-fastします。

```bash
flutter build apk --release
```

### live構成の境界

non-debug buildはdemo projectへfallbackしません。次の4つの `--dart-define` が不足すると `MissingLiveFirebaseConfiguration` でfail-fastします。

- `MICHIZURE_FIREBASE_API_KEY`
- `MICHIZURE_FIREBASE_APP_ID`
- `MICHIZURE_FIREBASE_MESSAGING_SENDER_ID`
- `MICHIZURE_FIREBASE_PROJECT_ID`

live設定、`.env`実値、signing keyをrepositoryへcommitしないでください。Phase 0はrelease signingとlive Firebase接続を構成しません。

Rules test用のFirebase CLIはローカル・CI限定のdevDependencyです。現行CLIの推移依存に `npm audit` 警告がある場合、`npm audit fix --force` で無検証downgradeせず、Firebase CLI更新時にRules testとともに見直します。

### 共有Firebaseと通知APIのデモ

通知APIは `services/notification_api/` のDockerイメージをRender Web Serviceとして起動します。Render Blueprintは [render.yaml](render.yaml) を使用し、health checkは `/health`、秘密値はDashboardで次の環境変数へ設定します。

- `FIREBASE_PROJECT_ID`: 共有Firebase project ID
- `FIREBASE_SERVICE_ACCOUNT_JSON`: Firebase Admin用service account JSON全文（Gitへ保存しない）

ローカル確認は `uv run --project services/notification_api uvicorn notification_api.main:app --host 0.0.0.0 --port 8080` で起動します。Androidアプリはlive Firebase用の4つの `MICHIZURE_FIREBASE_*` と、公開HTTPS URLを次のように指定します。

```bash
flutter run --profile -d emulator-5554 \
  --dart-define=NOTIFICATION_API_BASE_URL=https://example.onrender.com \
  --dart-define=MICHIZURE_FIREBASE_API_KEY=... \
  --dart-define=MICHIZURE_FIREBASE_APP_ID=... \
  --dart-define=MICHIZURE_FIREBASE_MESSAGING_SENDER_ID=... \
  --dart-define=MICHIZURE_FIREBASE_PROJECT_ID=...
```

複数人デモでは全員が同じ共有Firebaseへ接続し、Firebase Emulatorは使用しません。Google Play対応Android Emulatorを各自で起動し、別ユーザーでログインして同じグループへ参加し、通知権限を許可します。その後、Debt作成、スクワット救済、完済の順に別端末で通知を確認します。foregroundを含めて通知チャンネル`michizure_alerts_v1`のAndroid通知として表示され、通知タップでは対象Debtの詳細または返済画面を開きます。

2台確認では、一方をforeground、もう一方をbackgroundにしてDebt作成通知を確認し、次にアプリを終了した受信側へ救済または完済通知を送ります。各状態で通知が1件だけ表示され、タップ後に対象Debtへ遷移することを確認します。

AWS App Runnerへ移す場合は、同じDockerイメージをECRへpushし、container port `8080` のimage-based serviceを作成します。`FIREBASE_PROJECT_ID`は通常の環境変数、`FIREBASE_SERVICE_ACCOUNT_JSON`はSecrets Manager参照として渡し、その参照権限だけをinstance roleへ付与します。AWS resourceの作成とdeployはこのrepositoryでは行いません。

## デモと既知の制約

- デモ全手順、Device Owner provisioning、process kill / reboot、safe resetは [demo-plan.md](docs/demo-plan.md) を参照する。
- 任意アプリの強制封印は通常の個人Android端末では利用できず、managed Emulator / Android Enterprise管理端末が必要。
- 実カメラによるMediaPipe Lite精度とp50 / p95は物理端末またはhost webcamで当日確認する。synthetic unit testやEmulator値を物理端末性能として扱わない。
- `am force-stop`後はAndroidのstopped stateとなるため、明示的な再起動後にreconcileする。
- MICHIZUREをDevice Ownerにした端末では通常の自動uninstallが拒否されるため、integration testは`--no-uninstall`を使う。
