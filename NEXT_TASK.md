# NEXT TASK: Phase 1 `feature/auth-profile`

## この作業だけを実装する

Firebase Authenticationのemail/password登録・login・logoutと、本人だけが扱える `users/{uid}` profileの作成・表示・編集を実装する。

Group、Task、Device Owner、UsageStats、app lock、Debt、CameraX、ML Kit、スクワット機能は実装しない。Phase 2以降を先取りしない。

## 1. 作業開始

1. `README.md` と `AGENTS.md` を読む。
2. `docs/product-requirements.md`、`docs/architecture.md`、`docs/screen-flow.md`、`docs/data-model.md`、`docs/firestore-rules-design.md`、`docs/state-management.md`、`docs/security-privacy.md`、`docs/testing.md`、`docs/implementation-plan.md`、ADR 0001 / 0002を読む。
3. Phase 0のCIが成功し、`chore/project-bootstrap` が `dev` へ統合済みであることを確認する。
4. cleanな最新 `dev` からbranchを作る。

```bash
git fetch origin
git switch dev
git pull --ff-only origin dev
git switch -c feature/auth-profile
```

branchが既に存在する場合は作り直さず、履歴・差分・統合元を確認して続行する。

## 2. Scope

実装する画面:

- Splash / auth状態判定
- Login
- Register
- Profile Setup
- Profile / SettingsのPhase 1範囲
- 認証済み・profile作成済みユーザー向けの「Groupは次Phase」placeholder

実装する状態:

- `signedOut`
- `authenticatedWithoutProfile`
- `ready`
- loading
- recoverable error

認証方式はemail/passwordだけとする。social login、email verification、password reset、account deletion、avatar uploadはPhase 1外。

合理的仮定:

- passwordはclientで8〜128文字を要求する。
- `displayName` はtrim後1〜40文字。
- `photoUrl` はMVPでは常にnull。Storageを追加しない。
- Auth credentialのemailをFirestoreへ複製しない。
- logoutしても将来のnative Task / lock永続状態を消す仕様にはしない。

## 3. Architecture

feature-first + 4層を守る。

```text
lib/features/auth/
  domain/
    auth_user.dart
    auth_failure.dart
    auth_repository.dart
  application/
    auth_controller.dart
  infrastructure/
    firebase_auth_repository.dart
  presentation/
    login_screen.dart
    register_screen.dart
    widgets/
lib/features/profile/
  domain/
    user_profile.dart
    profile_failure.dart
    profile_repository.dart
  application/
    profile_controller.dart
  infrastructure/
    firestore_profile_repository.dart
  presentation/
    profile_setup_screen.dart
    profile_screen.dart
lib/app/
  router.dart
  providers.dart
```

空のUseCaseをCRUDごとに量産しない。Firebase型・Firestore `Timestamp`・`DocumentSnapshot`をDomain / Presentationへ漏らさない。Riverpodはmanual providerを使い、generatorを追加しない。

既存の `FirebaseGateway` はbootstrap責務のまま保つ。Auth/Profile repositoryを同クラスへ統合しない。

## 4. Firebase Authentication

- `FirebaseAuth.authStateChanges()` をRepositoryからDomain streamへ変換する。
- register、login、logoutをtyped result / typed failureで返す。
- Firebase error codeをPresentationで直接switchせず、Infrastructureで次へ変換する。
  - invalid email
  - weak password
  - email already in use
  - invalid credential
  - network unavailable
  - rate limited
  - unknown
- password、credential、ID tokenをlog・Firestore・local storageへ保存しない。
- submit連打を抑止し、処理中は入力とボタン状態を一貫させる。
- Auth user作成後にprofile createが失敗した場合は、認証済み/profile未作成状態としてProfile Setupへ復帰できるようにする。Auth userを勝手に削除しない。

debugはPhase 0のAuth Emulator `10.0.2.2:9099` を使用する。live FirebaseやCloud Functionsを追加しない。

## 5. `users/{uid}` data model

Phase 1で作成するdocumentは設計済みschemaに一致させる。

```text
users/{uid}
  displayName: string
  photoUrl: null
  groupId: null
  activeTaskSessionId: null
  createdAt: server timestamp
  updatedAt: server timestamp
  schemaVersion: 1
```

Repository要件:

- document IDはAuth UIDと同一。
- profile createは全fieldを1 writeで作る。
- profile取得は自分のdocumentを直接get/listenし、users collectionをlistしない。
- profile編集は `displayName`、`photoUrl`、`updatedAt` だけを変更する。
- converterはmissing field、unknown schemaVersion、型不正をtyped data failureにする。
- offline cache由来かserver由来かをUIが必要以上に区別しない。ただしwrite failureを成功表示しない。

Phase 1では `groupId` と `activeTaskSessionId` を変更するAPIをRepositoryへ公開しない。

## 6. Firestore Security Rules

default denyを維持したまま `users/{uid}` だけを最小開放する。

必要なhelper:

- signed-in判定
- `request.auth.uid == uid`
- keys完全一致
- displayName string / 1〜40文字
- nullable photoUrl（Phase 1 writerはnull）
- timestampが `request.time`
- schemaVersion 1

許可:

- 本人の `users/{uid}` direct read
- 本人によるschema完全一致のcreate
- 本人によるprofile fieldだけのupdate

拒否:

- 未認証read/write
- 他userのread/write
- users collection list
- client指定UIDとdocument ID不一致
- unknown / missing field
- `groupId`、`activeTaskSessionId`、`createdAt`、`schemaVersion`のprofile update
- delete
- invalid displayName / timestamp / type

Phase 2のgroup pointerやmember snapshot同期Ruleは実装しない。Rules変更と同じcommit系列でRules Testを追加する。

## 7. Router / UI

router redirectは次を単一のderived auth gateから判断する。

```text
auth loading                      -> Splash
signed out                        -> Login / Register
signed in + users/{uid} missing   -> Profile Setup
signed in + valid profile         -> Authenticated Placeholder
profile decode/read error         -> Recoverable Error
```

要件:

- redirect loopを起こさない。
- register成功後はProfile Setupへ進む。
- login成功時、profile有無を判定する。
- Profile画面で表示名を編集できる。
- logout後はLoginへ戻り、provider内のユーザー依存cacheを破棄する。
- loading / error / validationを画面内に明示する。
- Firebase例外文字列をそのままユーザーへ表示しない。
- Material 3と既存router shellを維持する。

Group onboardingの業務UIは作らず、次Phaseであることが分かる最小placeholderだけを置く。

## 8. Test

最低限:

### Dart unit

- Auth Firebase error → typed failure mapping
- Auth user mapper
- UserProfile validation / Firestore converter
- authenticated/profile missing/ready state derivation
- logoutでauth stateがsignedOutへ収束

### Widget

- Login validation、loading、failure、success
- Register validation、loading、failure、success
- Profile Setup validationとsubmit
- Profile表示・編集
- passwordが画面遷移後に残らない

### Router

- loading → Splash
- signed out → Login
- authenticated without profile → Profile Setup
- ready → authenticated placeholder
- logout → Login
- redirect loopなし

### Firestore Rules

- 本人create/get/valid profile update allow
- unauthenticated deny
- 他user get/update deny
- list/delete deny
- extra / missing field deny
- invalid name / schema / timestamp deny
- `groupId` / `activeTaskSessionId`改変deny

### Emulator integration

- register → profile create → logout → login → profile read
- Auth userだけ存在しprofileがない場合の復帰
- duplicate email error

テストでFirestore Rulesをbypassしたまま本処理を検証しない。Rules Testのseedだけ `withSecurityRulesDisabled` を使用できる。

## 9. Quality gate

commit前と最終確認で実行する。

```bash
./tool/check_all.sh
flutter build apk --debug
```

Android SDKが利用できない場合はAPK buildを未実行として明記し、CI結果を確認する。testをskip / weakenして通さない。

## 10. Dependency

Phase 0の `firebase_auth`、`cloud_firestore`、`flutter_riverpod`、`go_router` で実装する。原則として新規runtime dependencyを追加しない。

次は追加禁止:

- social auth SDK
- Firebase Storage
- code generator / Riverpod generator
- Freezed
- analytics / Crashlytics
- secure storage（passwordを保存しない）

やむを得ずdependencyを追加する場合は、目的・代替・license・minSdk・privacy影響をPRに記載する。

## 11. 推奨commit

各commit前に対象test、`git diff`、`git status`を確認する。

1. `feat: 認証ドメインとFirebase Auth repositoryを追加`
2. `feat: 登録とログイン画面を実装`
3. `feat: ユーザープロフィールを追加`
4. `test: 認証とusers Rulesを検証`
5. `docs: Auth/Profile実装手順を更新`

壊れた中間状態をcommitしない。最後に1 commitへsquashしない。

## 12. 完了条件

- Auth Emulatorでregister → profile → logout → loginが再現できる。
- auth userなし / profileなし / readyのrouter分岐が安定する。
- 本人以外はusers documentを読めず、本人も保護fieldを変更できない。
- email/password/tokenをFirestore・log・local storageへ保存しない。
- Flutter test、Rules Test、secret hygiene、Android debug buildが成功する。
- architecture変更なし。必要なら実装前にADRを追加する。
- live config / secretなし。
- clean worktree。
- branchは `feature/auth-profile`、PR targetは `dev`。

## 13. 完了報告

```text
Branch:
Commits:
Auth/Profile outcome:
Firestore schema / Rules / Index:
Dependencies:
Tests and exact results:
Android verification:
Privacy / security:
Known limitations:
PR URL or exact PR command:
Next phase (do not implement): feature/group
```
