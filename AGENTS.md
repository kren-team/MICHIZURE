# AGENTS.md

このファイルはrepository全体に適用する。後続のCoding Agentは、速度より設計・security・復元性を優先し、以下を必ず守る。

## 1. 作業前に読む

最低限、次を順番に読む。

1. `README.md`
2. `docs/product-requirements.md`
3. `docs/architecture.md`
4. 作業対象に対応する設計doc
5. `docs/firestore-rules-design.md`
6. `docs/security-privacy.md`
7. `docs/testing.md`
8. `docs/implementation-plan.md`
9. `NEXT_TASK.md`
10. `docs/adr/`

`NEXT_TASK.md`に書かれた1 Phaseだけを実装する。先のPhaseを「ついでに」実装しない。

## 2. Git branch

- `main`へ直接commit禁止。
- `dev`へ直接機能commit禁止。
- 最新`dev`から`feature/*`または`chore/*`を作る。
- 統合先は`dev`。
- `main`へmergeしない。
- force push禁止。
- rebase / amendで共有済み既存commitを書き換えない。
- `git reset --hard`、広範囲のcheckout、無関係なfile削除禁止。
- userや別Agentの未commit変更を勝手に戻さない。

開始時:

```bash
git status --short --branch
git branch --all
git log --oneline --decorate -10
```

新規branch:

```bash
git fetch origin
git switch dev
git pull --ff-only origin dev
git switch -c <NEXT_TASKのbranch>
```

既存branchやdirty worktreeがある場合は破壊せず、差分と意図を確認する。

## 3. Commit

- 1つの論理的・review可能な変更ごとにcommitする。
- 全作業を最後の1 commitへまとめない。
- 壊れた中間状態をcommitしない。
- Conventional Commit形式を使う。
- messageは変更の結果を具体的に書く。

commit前:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
git diff --check
git diff
git status --short
```

対象に応じてRules Test、Gradle test、instrumentationも実行する。まだproject bootstrap前でcommandが存在しない場合は、その事実を報告する。

## 4. Architecture

- Presentation / Application / Domain / Infrastructureの依存方向を守る。
- DomainからFlutter widget、Firebase、MethodChannelをimportしない。
- WidgetからFirestore documentを直接操作しない。
- Firebase / native payloadをInfrastructure adapterでDomainへ変換する。
- 複数Repository、native、outboxをまたぐ処理だけUseCaseにする。
- Riverpodをstate management / DIとして使用し、別方式を併用しない。
- UI TimerをTask成功・失敗のauthorityにしない。
- installed packageやcamera frameをDart business modelへ混入させない。

設計を勝手に変更しない。必要な場合:

1. 現行設計で不可能な根拠を示す。
2. alternativeとtrade-offを書く。
3. `docs/adr/NNNN-*.md`を追加する。
4. 影響するdocs、test、migrationを同じPRで更新する。

## 5. Firestore

- Security Rulesを後回しにしない。
- 新collection / field / queryと同じcommit系列でRules Testを追加する。
- default denyを維持する。
- `request.auth != null`だけのbroad writeを作らない。
- unknown fieldを拒否し、field allowlistを使う。
- Rulesはfilterではない。query constraintをRulesと一致させる。
- member count、Task pointer、Debt、Contribution aggregateはatomic invariantを守る。
- Debt残数をContribution全件から毎回集計しない。
- `FieldValue.increment`だけでDebtを加算しない。
- total超過防止にはTransactionとRules after-state検証を使う。
- transaction callbackからUI stateやnative commandを直接変更しない。
- Transactionはofflineで失敗するため、設計されたoutboxを無視しない。
- listenerを画面外でdetachし、無制限queryを作らない。
- composite indexとindex exemptionを`firestore.indexes.json`へ反映する。

Rules変更はFirebase Emulator Suiteでallow / deny両方をtestする。

## 6. Android native

- Device Owner前提はハッカソンmanaged Emulatorに限定する。
- 通常権限で`setPackagesSuspended`が可能だと仮定しない。
- app封印は`DevicePolicyManager.setPackagesSuspended`を使用する。
- foreign app検知はUsageStats + Foreground Service設計を守る。
- Activity lifecycleだけでfailureにしない。
- AccessibilityServiceをapp監視・封印目的で追加しない。
- Lock Task Modeへ方式変更しない。変更にはADRが必要。
- DPMのfailed package戻り値を無視しない。
- 複数Debtのlockをboolean 1個で管理しない。
- obligationのeffective unionを再計算してからreleaseする。
- logout、Activity終了、Firebase errorだけを理由にunsuspendしない。
- Platform Channelのversion、typed error、冪等event IDを守る。
- frame / bitmap / landmark列をPlatform Channelで毎frame送らない。
- Android manifest permission追加は用途、runtime flow、Play policy、testをPRへ書く。

## 7. Squat / Camera privacy

- Production detectorはCameraX + MediaPipe Pose Landmarker Liteを使用する。
- Camera画像・動画を保存しない。
- Camera画像・動画を外部送信しない。
- OpenAI APIをスクワット画像判定へ追加しない。
- raw landmark列をFirestore、analytics、crash logへ送らない。
- `ImageProxy`を全completion pathでcloseする。
- 1 frameを1 repとして数えない。
- 状態機械、confidence、hysteresis、minimum durationを守る。
- Fake / synthetic sourceはdebug / test source setだけに置く。
- release buildにFake route、channel command、debug bannerを含めない。
- fake由来eventをproduction dataとして偽装しない。
- 実ユーザー画像・動画をtest fixtureにしない。

## 8. Secret / Firebase config

commit禁止:

- service account JSON
- private key / OAuth secret
- App Check debug token
- Firebase CLI token
- signing keystore / password
- `.env`、`.env.*` の実値
- live project credential / CI secret

`google-services.json`と`firebase_options.dart`はFirebase server secretそのものではないが、このrepositoryではlive環境fileをcommitしない。`demo-*` Emulator用dummy / programmatic configだけを追跡できる。

- `.env.example`はkey名とdummy値だけ。
- live configはlocal / CI injection。
- debug tokenをlog、screenshot、issue、PRへ貼らない。
- project IDを起動時に検査し、releaseがdemoへsilent fallbackしない。
- secretらしき既存fileを見つけても内容を出力せず、追跡状況だけ報告する。

## 9. Logging

ログ禁止:

- auth token、email、invite raw token
- Task content
- package name / installed app inventory
- bitmap、frame、raw landmark
- full Firestore document
- App Check debug token

許可するのはopaque IDの短縮hash、state、latency、error code、package件数等。exception messageをそのままユーザー表示しない。

## 10. Testing responsibility

変更に応じて最低限追加する。

| Change | Required tests |
|---|---|
| Domain / UseCase | Dart unit |
| View | Widget |
| Firestore schema / query | Repository integration + index |
| Firestore Rules | allow / deny Rules Test |
| Transaction | concurrency / idempotency |
| Kotlin pure logic | JVM unit |
| Platform Channel | Dart/Kotlin contract |
| DPC / UsageStats | managed emulator instrumentation |
| CameraX / MediaPipe | analyzer + instrumentation |
| Recovery | process / network / boot matrix |

特に回帰させない:

- Debt = member数 × 10
- concurrent repayment
- totalReps超過防止
- Task / Lock / Debt再起動復元
- Task success / failure
- Debt completed / expired
- squat double count / shallow false positive
- screen off / keyguard誤failure
- 複数Debtの早期unlock

testをskip / weakenして通さない。flaky testは原因とownerを明記し、無期限skipしない。

## 11. Dependency

- standard library / existing dependencyで十分なら追加しない。
- dependency追加時はmaintainer、license、Android minSdk、binary size、privacy、release cadenceを確認する。
- current versionを公式sourceで確認しlockfileをcommitする。
- abandoned pluginでAndroid native capabilityを迂回しない。
- Firebase、MediaPipe、CameraXのversionを無根拠に一斉upgradeしない。
- code generator追加はADRまたは明確な反復削減根拠が必要。

## 12. Docs

- codeとdocsが矛盾する変更をmergeしない。
- schema、state、channel、permission、runbook変更は同じbranchで該当docを更新する。
- Mermaidを変更したらfenceとsyntaxを確認する。
- `README.md`のdoc indexと`NEXT_TASK.md`を必要に応じ更新する。
- 実装済みでないものを完了と書かない。

## 13. 作業範囲

- `NEXT_TASK.md`のin-scopeだけを実装する。
- unrelated refactor、format全体変更、dependency upgradeを混ぜない。
- 診断依頼では勝手にfixしない。
- 実装依頼では合理的な範囲のtestまで完了する。
- 外部deploy、live Firebase mutation、PR作成は依頼と権限の範囲で行う。
- destructiveなAVD wipeやdata削除は対象を確認し、デモ専用であることを明示する。

## 14. PR

targetは`dev`。GitHub CLIが認証済みなら、依頼範囲内でPRを作成してよい。認証されていない場合は無理にloginせず、実行すべきcommandを提示する。

PR本文:

```text
Branch:
Target: dev
Purpose:
Architecture / ADR impact:
Firestore schema / Rules / Index:
Android permission / manifest:
Privacy impact:
Tests run and results:
Manual Emulator verification:
Commits:
Known limitations:
Next phase:
```

## 15. 完了報告

必ず次を報告する。

1. 実装したoutcome
2. branch
3. commit一覧
4. 主要変更file
5. 実行したtestと結果
6. 実行できなかったtestと理由
7. Firestore / Rules / Index差分
8. Android permission / native差分
9. privacy / securityへの影響
10. known limitation
11. PR URLまたは正確なPR command
12. 次の1 Phase（実装はしない）

曖昧な「テスト済み」ではなくcommandとpass件数・対象を示す。
