# NEXT TASK: Phase 9 `feature/squat-detection`

## 目的

CameraX + ML Kit Pose DetectionをAndroid端末内で実行し、Kotlinの決定的な状態機械が受理したスクワット1回をPhase 8の`ContributionController.recordAcceptedRep()`へ渡す。

Camera画像・動画・raw landmarkは保存せず、外部送信しない。Phase 8のFirestore transaction、Outbox、Debt realtime、App Lock解除を作り直さない。

## Branch

```bash
git fetch origin
git switch dev
git pull --ff-only origin dev
git switch -c feature/squat-detection
```

## 最初に読む

1. `AGENTS.md`
2. `README.md`
3. `docs/architecture.md`
4. `docs/squat-detection.md`
5. `docs/data-model.md`
6. `docs/state-management.md`
7. `docs/security-privacy.md`
8. `docs/testing.md`
9. `docs/implementation-plan.md`
10. `docs/adr/0004-on-device-pose-detection.md`

## In scope

### Android / Kotlin

- CameraX `Preview` + `ImageAnalysis`
- `STRATEGY_KEEP_ONLY_LATEST`とsingle analyzer executor
- ML Kit base Pose Detection bundled model / `STREAM_MODE`
- frame rotation / front camera mirrorの正規化
- landmark quality gate、side selection、angle / hip drop / velocity feature
- median + EMA smoothing
- `CALIBRATING → STANDING → DESCENDING → BOTTOM → ASCENDING → STANDING`
- depth、ROM、minimum duration、hysteresis、refractoryによる1 cycle 1 rep
- success / failure / cancellationを含む全pathで`ImageProxy.close()`
- lifecycle-safe start / stop / duplicate command

### Flutter / Native contract

- versioned typed Method/Event Channel
- Dartへ送るのはquality、FSM state、accepted rep event、最小latency metadataのみ
- rep eventごとにstable `squatSessionId` + monotonic `sequence`
- Phase 8の`ContributionRequest`へ変換し`recordAcceptedRep()`を呼ぶ
- frame、bitmap、landmark列をPlatform Channelへ送らない

### UI

- Camera permissionとrationale
- Squat setup、全身を映すガイド、calibration状態
- preview、quality warning、detected / pending / confirmed
- 選択したDebt IDと残回数
- terminal Debt / route離脱でcameraとanalyzerを停止

### Debug / test

- synthetic feature/landmark sourceはdebug/test source setだけ
- Fake rep commandをrelease artifactへ含めない
- debug source使用時は明確なbanner
- 実ユーザー画像・動画をfixtureにしない

## Out of scope

- Cloud/OpenAI画像判定
- Camera frame / landmarkの保存・送信
- 複数人tracking
- Contribution transaction / Rulesの再設計
- App Lock obligation方式の変更
- Phase 10 recovery全般
- Phase 11 polish

## 必須不変条件

- 1 frameを1 repとして数えない。
- STANDINGから始まりBOTTOMを経てSTANDINGへ戻った有効cycleだけ1 rep。
- shallow motion、bottom bounce、tracking loss、極端なframe gapでcountしない。
- frame / bitmap / raw landmarkはDart、Firestore、analytics、logへ出さない。
- `ImageProxy`は全completion pathで必ずcloseする。
- Phase 8の1 rep / immutable event / Outbox冪等性を維持する。
- release buildにFake/Synthetic選択routeやdebug event commandを含めない。

## Acceptance Criteria

- 有効なスクワットcycleだけが1つのPhase 8 eventを生成する。
- shallow、jitter、二重bottom、tracking loss、しゃがみ開始で誤countしない。
- Camera/ML Kit結果からUI counter反映までp95 500ms目標を計測できる。
- permission拒否、camera unavailable、ML failureをtyped failureとして表示する。
- route離脱・terminal Debt・process lifecycleでcamera resourceを解放する。
- accepted repがpending / confirmed / rejectedへPhase 8経路で遷移する。
- Android debug Emulatorではsynthetic sourceで決定的デモができ、releaseには含まれない。

## Tests

- Kotlin pure FSM table test: valid cycle、shallow、bounce、tracking loss、duration、ROM、refractory
- feature / angle / smoothing / side-selection unit
- analyzer: rotation、mirror、latest-frame、全path `ImageProxy.close`
- Platform Channel contract/version/invalid payload
- Flutter Widget: permission、calibration、quality、counter、pending/confirmed/rejected
- Android instrumentation: CameraX lifecycle、ML Kit initialization、latency
- release artifact / manifestにFake routeがないこと
- Phase 1〜8回帰、Rules Test、Contribution統合テスト

## 推奨commit分割

1. `feat: Pose featureとquality gateを追加`
2. `feat: スクワット状態機械を実装`
3. `feat: CameraXとML Kitを統合`
4. `feat: Squat native contractとUIを接続`
5. `test: スクワット誤検出とlifecycleを検証`
6. `docs: Phase 9結果と次Phaseを更新`

## 停止条件

Phase 9完了後は停止する。Phase 10 recovery / reconciliationは開始しない。
