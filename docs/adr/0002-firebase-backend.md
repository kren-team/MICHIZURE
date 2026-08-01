# ADR 0002: MVP backendをFirebase Auth + Firestore clientに限定する

- Status: Accepted
- Date: 2026-07-26

## Context

グループ、Debt、Contributionを複数Emulatorでリアルタイム同期し、初期MVPをSpark Planでほぼ無料にする必要がある。Cloud Functionsを必須にするとBlaze Planとdeploy運用が必要になる。一方、clientだけではtrusted time、poseの真正性、管理者権限による不正防止を完全には実現できない。

## Decision

- 認証はFirebase Authenticationのemail/password。
- 共有永続化はCloud Firestore Standard editionの1 database。
- client transaction、deterministic ID、Security Rules `getAfter()`で原子的整合性を検証する。
- Cloud Functions、Cloud Run、Storage、OpenAI APIをMVP必須経路に入れない。
- 開発・CI・主デモではFirebase Local Emulator Suiteを使用できるようにする。
- live backupはSpark Planのregional Firestoreを日本のユーザーに近いlocationへ作る。
- Productionではtrusted backend導入を再検討する。

## Consequences

### Positive

- payment methodなしでデモを構成できる。
- Flutter SDKのoffline cacheとsnapshot listenerを直接利用できる。
- Rules TestをEmulatorで高速に回せる。
- 運用コンポーネントが少ない。

### Negative

- clientはfake detectorや改変版アプリからrepを書ける。
- Transactionはofflineで失敗し、outboxが必要。
- failure時刻とTask開始時刻は完全なserver authorityではない。
- status expirationは接続中clientが遅延評価するため、誰も接続しない間はFirestore上 `active` が残り得る。
- hotspotとread quotaをclient設計で監視する必要がある。

## Why Cloud Functions is not required for MVP

1. Debt量はRulesで `memberCountAtFailure * 10` と検証できる。
2. Contribution上限はDebtを読むTransactionとRulesのafter-state検証で守れる。
3. expirationはRulesの `request.time` とclient transactionで安全に遷移できる。
4. Emulator Suiteは本番backendの代替ではないが、デモ自体はローカルで再現できる。

## Production trigger

次のいずれかが必要になればBlaze + trusted backendを設計する。

- 金銭・賞品・ランキング等で不正防止が重要
- client-generated failure / repを信用できない
- 全Debtを時刻通りにexpireする必要
- push notification、監査、管理者操作が必要
- Spark quota超過または可用性保証が必要

## Rejected alternatives

- Realtime Database: simple presenceには適するが、複数document transaction、query、RulesでFirestoreの方が要件に合う。
- 独自REST backend: 信頼境界は改善するが、ハッカソンの構築・運用コストが高い。
- Cloud Functions必須: Blaze依存となり、MVPの無料優先と衝突する。
- client `FieldValue.increment`のみ: totalReps超過をclampできないため不採用。

## References

- [Firestore transactions](https://firebase.google.com/docs/firestore/manage-data/transactions)
- [Secure atomic operations with getAfter](https://firebase.google.com/docs/firestore/manage-data/transactions#data_validation_for_atomic_operations)
- [Firebase pricing plans](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans)
- [Local Emulator Suite](https://firebase.google.com/docs/emulator-suite)
