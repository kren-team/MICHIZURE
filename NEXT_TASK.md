# NEXT TASK: Phase 0 `chore/project-bootstrap`

## この作業だけを実装する

Android専用Flutter project、Firebase Local Emulator Suite、default-deny Firestore Rules、最低限のCIを構築する。

Auth、Group、Task、Device Owner、UsageStats、app lock、Debt、CameraX、ML Kit、スクワットUIは実装しない。次Phaseの先取りを禁止する。

## 1. 作業開始

1. `README.md`, `AGENTS.md`, `docs/product-requirements.md`, `docs/architecture.md`, `docs/state-management.md`, `docs/firestore-rules-design.md`, `docs/implementation-plan.md` を読む。
2. 作業ツリーとbranchを確認する。
3. 設計branchが`dev`へ統合済みであることを確認する。
4. 最新`dev`からbranchを作る。

```bash
git fetch origin
git switch dev
git pull --ff-only origin dev
git switch -c chore/project-bootstrap
```

既にbranchが存在する場合は破壊せず、履歴と差分を確認して続行する。

## 2. Flutter skeleton

要件:

- project name: `michizure`
- applicationId / namespace: `com.kren.michizure`
- Android only
- minSdk 23
- Kotlin
- Material 3
- existing README / AGENTS / docs / `.github/CODEOWNERS` を上書きしない

既存repository直下へ`flutter create`を直接実行してtracked docsを上書きしない。private temp directoryへ生成し、生成差分を確認して必要なfileだけ統合する。

予定構成:

```text
lib/main.dart
lib/app/app.dart
lib/app/bootstrap.dart
lib/app/router.dart
lib/core/error/
lib/core/time/
lib/core/platform/
test/app/
android/
```

placeholder appは「Bootstrap OK」とenvironmentを表示するだけにする。ユーザー向けfeature画面は作らない。

## 3. Dependency

Phase 0で追加してよいruntime dependency:

- `firebase_core`
- `firebase_auth`
- `cloud_firestore`
- `firebase_app_check`
- `flutter_riverpod`
- `go_router`

実際に使わないdependencyを追加しない。versionは作業時点のFlutter / Android互換性を公式release notesで確認し、`pubspec.lock`をcommitする。

次はまだ追加しない。

- CameraX / ML Kit
- WorkManager wrapper
- permission helper
- code generator / Riverpod generator
- Freezed / json generator
- analytics / Crashlytics
- OpenAI SDK

## 4. Firebase Emulator baseline

作成:

```text
firebase.json
.firebaserc
firestore.rules
firestore.indexes.json
firebase/rules-tests/package.json
firebase/rules-tests/src/default-deny.test.*
```

設定:

- project alias / ID: `demo-michizure`
- Auth Emulator: 9099
- Firestore Emulator: 8080
- Emulator UI: 4000
- single project mode
- Android debug host: `10.0.2.2`

`firestore.rules`:

- `rules_version = '2'`
- すべてのdocument read/writeを拒否
- temporary broad allow禁止

Rules Test:

- unauthenticated get/create/update/delete deny
- authenticated get/create/update/delete deny
- testは`@firebase/rules-unit-testing`を使用
- testごとにdataをclear

実装開始前にFirebase CLI / Java / Nodeの利用可能versionを確認する。dependency installがnetwork承認を必要とする場合は正規の承認を求める。

## 5. Firebase initialization

- debug/demoのprogrammatic `FirebaseOptions`だけをrepositoryへ置ける。
- initialize直後、SDK初回利用前にAuth / Firestore Emulatorへ接続する。
- debug placeholderへproject IDとEmulator接続状態を表示する。
- release / live configがない場合はfail-fastし、demo projectへsilent fallbackしない。
- App Check debug tokenを生成・commitしない。

commit禁止:

- live `google-services.json`
- live `firebase_options.dart`
- `.env`実値
- service account
- App Check debug token
- signing key

`.gitignore`とdummy-only `.env.example`方針を整える。

## 6. Quality tooling

最低限:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Rules:

```bash
cd firebase/rules-tests
npm test
```

CI:

- Flutter format / analyze / test
- Firestore Rules Test
- secret scan相当の基本check
- live Firebaseへ接続しない
- Android full buildは可能なら追加。環境時間を大きく増やす場合は別job

CIとlocalで異なるcommandを増やさず、scriptまたはdocumentに一元化する。

## 7. 最低限のtest

- placeholder app renders
- router initial location
- bootstrap success
- debug project ID is `demo-michizure`
- release configなしはtyped failure
- default-deny Rules全operation

Phase 0でAuth機能test、group fixture、Task entityを作らない。

## 8. 推奨commit

各commit前に対象test、`git diff`、`git status`を確認する。

1. `chore: Flutter Androidプロジェクトを初期化`
2. `chore: Firebase Emulator Suite基盤を追加`
3. `test: default-deny Firestore Rulesを検証`
4. `ci: FlutterとRulesの品質ゲートを追加`
5. `docs: ローカルbootstrap手順を追記`

壊れた中間状態をcommitしない。最後に1 commitへsquashしない。

## 9. 完了条件

- Android emulatorでplaceholder app起動
- applicationId `com.kren.michizure`
- minSdk 23
- Auth / Firestore Emulator接続
- default-deny Rules Test成功
- format / analyze / Flutter test成功
- CI定義成功、またはlocalでCI相当command成功
- 既存設計docsに意図しない変更なし
- live config / secretなし
- clean worktree
- branchは`chore/project-bootstrap`
- PR targetは`dev`

## 10. 完了報告

```text
Branch:
Commits:
Generated project / tool versions:
Dependencies added:
Firebase Emulator ports:
Tests and results:
Android launch verification:
Files intentionally not added:
Known limitations:
PR URL or exact PR command:
Next phase (do not implement): feature/auth-profile
```
