# コスト・Firestore read見積もり

## 1. 結論

MAU 1,000 / DAU 100、平均group 5の想定なら、Firebase Authentication + Cloud FirestoreはSpark Planの無料枠内でMVP運用できる可能性が高い。主な変動要因はスクワット1repごとの3 writesと、Debt doc更新を見ているオンライン端末数である。

Cloud FunctionsはMVPで使わないためBlaze Planは不要。主デモをLocal Emulator SuiteにすればFirestore/Authのcloud usage自体が発生しない。

## 2. 2026-07-26時点の無料枠

Cloud Firestore free quota:

| Resource | Free quota |
|---|---:|
| Stored data | 1 GiB |
| Document reads | 50,000 / day |
| Document writes | 20,000 / day |
| Document deletes | 20,000 / day |
| Outbound transfer | 10 GiB / month |
| Free database | 1 / project |

quotaは概ねPacific timeの深夜にdaily resetする。TTL delete、backup、PITR等は無料対象外でありMVPでは使わない。

Firebase Authenticationはemail/passwordを使用し、目標DAU 100はSparkの該当上限より十分小さい。phone authは使用しない。

## 3. 基準シナリオ

仮定:

- DAU 100
- 1 userあたり1 Task/day
- failure率20% = 20 Debts/day
- 平均group size 5
- 1 Debt = 50 reps
- 合計1,000 accepted reps/day
- 1 rep transaction = Debt + Contribution Event + member summary
- group dashboardを1 user 1回/day
- active Debt初期表示は平均2件
- Debt更新時に平均2台のgroup dashboard、1台のDebt detailがlistener中

### 3.1 Writes

| Operation | 計算 | Writes/day |
|---|---:|---:|
| Task start | 100 × (task + user) | 200 |
| Task success | 80 × (task + user) | 160 |
| Task failure | 20 × (task + user + debt) | 60 |
| Contributions | 1,000 × (debt + event + summary) | 3,000 |
| profile/group/invite/expiry buffer | assumption | 200 |
| **Total** |  | **3,620** |

free 20,000 writes/dayの約18%。failure率やgroup sizeが上がっても基準値には余裕がある。

### 3.2 Reads

| Operation | 計算 | Reads/day |
|---|---:|---:|
| app shell user | 100 × 1 | 100 |
| group dashboard initial | 100 × (group 1 + members 5 + debts 2) | 800 |
| Task transactions / restore | estimate | 600 |
| rep transaction reads | 1,000 × 3 | 3,000 |
| Debt realtime fanout | 1,000 × 2 dashboards | 2,000 |
| Contribution summary fanout | 1,000 × 1 detail | 1,000 |
| Debt detail initial | 100 views × (debt 1 + summaries 5) | 600 |
| Rules access / reconnect / history buffer | estimate | 3,000 |
| **Total** |  | **11,100** |

free 50,000 reads/dayの約22%。Rulesの`get()` / `getAfter()`は課金readになり得るためbufferを含めた。実装後はFirebase UsageとEmulator workloadから補正する。

## 4. 最大40人groupのスパイク

1 failureで `40 × 10 = 400 reps`。

- rep writes: `400 × 3 = 1,200`
- rep transaction reads: `400 × 3 = 1,200`
- 40人全員がgroup dashboardを開いたままならDebt updateだけで最大 `400 × 40 = 16,000 reads`
- 10人がDebt detailを開いていればsummary updateで追加約4,000 reads

1つの最大groupイベントだけならfree read quota内だが、同日複数回や他group負荷が重なるとSparkを圧迫する。最大人数は機能上許可しつつ、デモや通常運用では画面外listenerをdetachし、quota alertを監視する。

## 5. Read削減策

- member表示名をmember docへdenormalizeしusersへのN+1 readをなくす。
- Debt `completedReps` を集計値として保持しeventsを読まない。
- active Debt queryはlimit 20。
- Contribution listenerはDebt detail / Squat画面だけ。
- historyはsnapshot listenerでなくcursor pagination。
- app lifecycleがbackgroundになりlock処理も不要ならlistenerをdetach。
- 同一screen内でProviderを共有し重複listenerを作らない。
- offline persistence有効でも30分以上切断後のreconnectは新規query相当になり得るため考慮する。
- p95 1秒を維持できる範囲で、将来は複数repを最大1秒windowでbatchする案をload testする。ただしMVPは1 event = 1 repを優先する。

## 6. Write / contention対策

- Debt docは全repで更新されるhot document。平均5人、1人2秒/repなら概ね2.5 writes/secでMVP規模。
- Firestoreのsingle document許容量はworkload依存で固定値を仮定しない。
- `STRATEGY_KEEP_ONLY_LATEST` とstate machineにより誤った高頻度repを生成しない。
- Rulesで1 event 1 rep、任意に最短rep間隔を検討する。
- transaction retry回数とlatencyを計測する。
- 最大40人同時返済の負荷試験でcontention / aborted率を確認する。
- Production scaleでhotspotになる場合はsharded counters + trusted aggregationを検討するが、厳密な上限clampが複雑になるためMVPでは採用しない。

## 7. Storage概算

1 Contribution Eventをindex込みで概算1〜2 KiBとすると、1,000 reps/dayで約1〜2 MiB/day。その他documentを含めても1 GiB到達には数か月〜年単位だが、MVPで自動削除しないため継続運用では保持policyが必要。

90日保持の単純概算:

```text
1,000 events/day × 2 KiB × 90 ≒ 176 MiB
```

index fanoutで増えるため、queryしないevent fieldはindex exemptionする。

## 8. Emulator Suite

主デモ:

- Auth Emulator
- Firestore Emulator
- Security Rules
- `demo-michizure` project ID

利点:

- cloud read/write費用ゼロ
- internet不調の影響を削減
- seed/reset可能
- Rules request traceを確認可能

Emulator Suiteはproduction hostingではなく、性能・security・可用性の代替ではない。p95 SLOはlive regional Firestoreでも別途測定する。

## 9. Blazeへ移る条件

- daily usageがfree quotaの70%を継続的に超える
- quota超過によるサービス停止を許容できない
- trusted Cloud Functions / Cloud Runが必要
- scheduled expiration / cleanup / push fanoutが必要
- backup、PITR、TTLが必要

Blaze移行時:

- budget alertを設定する。ただしalertはspending capではない。
- App Check、rate limit、quota dashboardを有効化する。
- 読み書き単価はregionと当時のprice calculatorで再見積もりする。
- FunctionsのinvocationだけでなくFirestore read/writeとegressを合算する。

## 10. SLOと測定

| Metric | Instrument |
|---|---|
| transaction p50/p95/p99 | client monotonic timer、operation name |
| writer→peer snapshot | event IDのserver ack / peer receive |
| reads/writes/day | Firebase Usage dashboard |
| transaction retry/abort | typed repository metrics |
| listener count | debug diagnostics |
| Debt doc write rate | local aggregated metrics、個人情報なし |

cache snapshotはnetwork latency測定から除外し、`hasPendingWrites` とsourceを記録する。

## 11. 公式資料

- [Firestore usage and limits](https://firebase.google.com/docs/firestore/quotas)
- [Understand Firestore billing](https://firebase.google.com/docs/firestore/pricing)
- [Firebase pricing plans](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans)
- [Firebase Authentication limits](https://firebase.google.com/docs/auth/limits)
- [Firestore best practices](https://firebase.google.com/docs/firestore/best-practices)
