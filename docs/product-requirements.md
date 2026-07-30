# プロダクト要件とMVPスコープ

## 1. 目的

MICHIZUREは、個人の集中タスク失敗をグループの共同スクワット負債へ変換し、仲間とのリアルタイムな返済体験によって行動変容を促すAndroid専用アプリである。

この設計の優先順位は次の通り。

1. Android Emulatorで再現性の高いハッカソンデモ
2. 端末外へカメラ画像を出さないプライバシー
3. Firebase Spark Planでの無料運用
4. タスク・ロック・Debtの再起動復元
5. Production化できる境界とリスクの明示

## 2. 用語

| 用語 | 定義 |
|---|---|
| Task Session | 内容、実行時間、開始・終了時刻を持つ1回の集中タスク |
| foreign app | MICHIZURE以外で、除外対象でないフォアグラウンドActivityのパッケージ |
| failure | 実行中にユーザー操作と判断できるforeign app遷移が確定した状態 |
| Debt | 1回のfailureにつき1つ作られる、グループで返済するスクワット回数 |
| Contribution | あるユーザーが特定Debtに対して確定させた返済回数 |
| Lock obligation | 1つのDebtが失敗ユーザーの端末に課す封印理由 |
| effective lock | 未完済かつ期限内のlock obligationすべてが要求するパッケージの和集合 |

## 3. MVPの確定スコープ

### 3.1 ユーザー

- Firebase Authenticationのメールアドレス・パスワード方式で登録、ログイン、ログアウトできる。
- 表示名とプロフィールを表示・編集できる。
- 電話番号認証、ソーシャルログイン、パスワードレス認証はMVP外。

### 3.2 グループ

- 作成、招待コード発行、コード参加、メンバー一覧、退出ができる。
- 1ユーザーは同時に1グループだけに所属する。
- 最大40人。通常規模は約5人。
- ownerはowner権限を他メンバーへ移譲するまで退出できない。
- グループ削除、複数グループ、招待リンクのOS連携はMVP外。

### 3.3 Task Session

- Taskを開始するにはログイン、グループ所属、Device Owner、利用状況アクセス、封印対象アプリ1件以上が必要。
- 内容は1〜100文字、実行時間はMVPで1〜180分とする。
- 開始後はMICHIZURE内でカウントダウンする。
- 正常終了までforeign app遷移がなければ `succeeded`。
- ユーザーによる中断、監視権限の喪失、ユーザー操作と確定したforeign app遷移は `failed`。
- running中に「キャンセルして無かったことにする」操作は提供しない。中断確認後はfailureとして扱う。
- 実行中はKotlin Foreground Serviceの継続通知を常時表示する。

### 3.4 アプリ封印

- ユーザーはランチャーから起動可能なインストール済みアプリから対象を選ぶ。
- MICHIZURE自身、active launcher、permission controller、default dialer、Device Admin、installer等、OSが停止を許さないパッケージは選択不可。
- failure確定時、選択済み一覧をDebt単位で端末ローカルにsnapshotし、即時に封印する。
- 解除条件は、そのDebtが `completed` になるか `lockExpiresAt` を過ぎること。
- 複数Debtがある場合、同じパッケージに対する未解決obligationが1件でも残る限り解除しない。
- パッケージ一覧はFirestoreへ送らず、端末ローカルだけに保存する。

### 3.5 Debtと返済

- failure時点の `memberCount × 10` を `totalReps` とする。
- 1 failure = 1 Debt。Debt IDはTask Session IDと同一にして重複作成を防ぐ。
- 同時に複数Debtを保持できる。
- 返済者はDebtを明示的に選択する。
- 1回の確定スクワットにつき、冪等なContribution Eventを1件作り、Firestore TransactionでDebt集計とユーザー集計を同時更新する。
- `completedReps` は `totalReps` を超えない。
- `request.time >= lockExpiresAt` のContributionは拒否し、Debtは `expired` へ収束させる。

### 3.6 スクワット判定

- Production実装はCameraX + ML Kit Pose Detectionのbase SDK / stream modeを使用する。
- カメラ画像・映像は保存、ログ出力、Firestore送信、外部API送信をしない。
- 33ランドマークのうち片側の股関節・膝・足首を必須入力とし、膝角度、正規化した腰の沈み、速度、信頼度、時間、ヒステリシスを持つ状態機械で1repを確定する。顔・肩は必須にしない。
- debug buildに限り、UI操作または合成ランドマーク列を供給する `FakeSquatDetector` をDIできる。
- debug detector由来のContributionはメタデータで識別し、Production buildにはFake実装を含めない。

## 4. 明示する合理的仮定

未確定要件は作業停止理由にせず、MVPでは以下を採用する。

| 項目 | MVPの仮定 | 変更点 |
|---|---|---|
| Android applicationId | `com.kren.michizure` | Firebase登録前なら変更可。変更時はADR |
| デモAPI level | API 35のGoogle APIs / Google Play対応Emulatorを基準 | 実装時のCI対応状況で固定 |
| Android minSdk | 23 | ML Kit / FlutterFireの現行下限 |
| hard enforcement対応 | API 29以上、Device Owner端末 | API 23〜28はUIを起動可能でもMVP保証外 |
| lock期間 | failureから30分 | debug flavorはデモ用に短縮可 |
| Debt単価 | failure時メンバー1人あたり10rep | 変更は新規Taskにだけ適用 |
| 同時running Task | ユーザーごとに1件 | `users/{uid}.activeTaskSessionId` とTaskをatomic更新 |
| group未所属Task | 開始不可 | 個人DebtはMVP外 |
| タスク中の着信 | 着信中のdefault dialer遷移は失敗にしない | 実機テスト必須 |
| OS権限画面 | Task開始前preflightで必要権限を完了し、アプリ起点の短い許可画面のみ除外 | 任意Settings遷移はfailure |
| オフラインfailure | ローカルで即封印し、failureをoutboxに保存。Debt共有は再接続後 | 完全なオフライン共同同期は不可能 |
| deadline競合 | deadline前にcommitした完済が勝ち、deadline以降の返済は拒否 | `request.time` をRulesで使用 |

## 5. Taskの受け入れ条件

- `startedAt`、`durationSec`、`expectedEndAt` を永続化する。
- 稼働中は `SystemClock.elapsedRealtime()` に基づいて終了を判定し、壁時計変更の影響を抑える。
- 再起動時は保存した `expectedEndAt` とboot情報から復元・再評価する。
- Task開始処理がクラウドへ未確定なら監視を開始しない。
- failure確定後は端末ロックをFirestore反映より先に行う。
- 同一Taskが `succeeded` と `failed` の両方になることはない。
- success時はDebtもlock obligationも作らない。

## 6. 誤判定防止の要件

次はその事象だけを理由にfailureにしない。

- 画面OFF、ambient display
- Keyguard表示
- OSが表示した着信画面
- MICHIZUREが明示的に開始した権限ダイアログ
- 構成変更によるActivity再生成
- 自アプリ内Activity / Flutter route遷移

次はfailure候補である。

- Home、Recents、別アプリをユーザーが開いた
- notificationから別アプリを開いた
- split screenで別アプリがtop-resumedになった
- Task中に利用状況アクセスまたは監視通知をユーザーが無効化した
- ユーザーがTaskを明示中断した

UsageStatsは遷移理由そのものを提供しないため、完全な意図推定は不可能である。MVPでは画面・Keyguard・通話・自アプリが開始したsystem flow・短いdwell timeを組み合わせ、残余リスクをテスト結果とともにデモ説明へ含める。

## 7. 状態復元とネットワーク

### 7.1 ローカルを先に信用する状態

- running TaskのID、開始単調時刻、期待終了時刻
- 未同期failure outbox
- Debtごとのロック対象snapshot
- 現在OSへ適用したsuspended package集合
- 次のlock deadline

### 7.2 Firestoreを正とする状態

- ユーザー、グループ、メンバー
- Taskの共有可能な最終状態
- Debt、completedReps、status
- メンバー別Contribution

再接続時は「ローカル未同期イベントを冪等に送信 → Firestore snapshotを受信 → effective lockを再計算 → OS状態と差分同期」の順に収束させる。Debt完済をオフライン端末が知らない場合、deadlineまでは安全側に倒して封印を維持する。

## 8. 非機能目標

| 指標 | 目標 | 測定境界 |
|---|---|---|
| 通常のFirestore操作 | p95 500ms以内 | client request開始〜server ack、キャッシュ即時反映を除外 |
| リアルタイム同期 | p95 1秒以内 | writer server ack〜別オンライン端末snapshot |
| スクワット表示 | p95 500ms以内 | CameraX frame timestamp〜UI rep表示 |
| foreign app確定 | 目標1秒以内 | ACTIVITY_RESUMED〜failure確定。600ms前後の誤判定防止dwellを含む |
| 可用規模 | MAU 1,000 / DAU 100 | 平均グループ5、最大40 |

Firebaseと公衆インターネットにはMVPのSLAがないため、これらは保証値ではなく計測するSLOである。

## 9. MVP外

- iOS、Web
- 通常の個人端末での強制アプリ封印
- Cloud Functions、独自サーバー、OpenAI API
- 動画アップロード、カメラ録画
- 完全なチート防止、root端末対策、Device Owner解除対策
- FCM push通知
- 複数人を同時認識するpose detection
- owner不在のグループ、グループ履歴の完全監査
- 管理コンソール、モデレーション、アカウント削除ワークフロー

## 10. Productionへ進む条件

- コンシューマー版かAndroid Enterprise版かを事業判断する。
- DPC承認、managed provisioning、scoped package visibility、Foreground Service申告を審査する。現構成では`QUERY_ALL_PACKAGES`を使用しない。
- trusted backendでTask failure、Debt生成、Contribution検証、時刻を権威化する。
- App Check Play Integrityを強制し、debug providerを完全分離する。
- abuse、監査、削除要求、データ保持期間、サポート導線を整備する。
- ML Kit Pose Detection betaの更新・破壊的変更を吸収するcompatibility testを持つ。

## 11. 公式仕様

- [DevicePolicyManager.setPackagesSuspended](https://developer.android.com/reference/android/app/admin/DevicePolicyManager#setPackagesSuspended(android.content.ComponentName,%20java.lang.String%5B%5D,%20boolean))
- [UsageStatsManager](https://developer.android.com/reference/android/app/usage/UsageStatsManager)
- [UsageEvents.Event](https://developer.android.com/reference/android/app/usage/UsageEvents.Event)
- [ML Kit Pose Detection for Android](https://developers.google.com/ml-kit/vision/pose-detection/android)
- [Cloud Firestore transactions](https://firebase.google.com/docs/firestore/manage-data/transactions)
- [Firebase pricing plans](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans)
