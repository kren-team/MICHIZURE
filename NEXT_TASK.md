# NEXT TASK: Phase 2 `feature/group`

## この作業だけを実装する

グループの作成、招待、参加、リアルタイムのメンバー一覧、所有者移譲、退出制約を実装する。Phase 1の認証・プロフィールと `users/{uid}` Rulesを前提にする。

Task、Device Owner、UsageStats、app lock、Debt、CameraX、ML Kit、スクワット判定は実装しない。Firebase Storage、Cloud Functions、Firebase Admin SDKも追加しない。

## 作業開始

1. `README.md`、`AGENTS.md`、`docs/data-model.md`、`docs/firestore-rules-design.md`、`docs/state-management.md`、`docs/testing.md`、`docs/implementation-plan.md` のPhase 2を読む。
2. 最新のcleanな `dev` から開始する。`feature/auth-profile` は直接の統合元にしない。

```bash
git fetch origin
git switch dev
git pull --ff-only origin dev
git switch -c feature/group
```

## 必須設計制約

- 一人が所属できるgroupは一つだけ。最大40人。
- group作成は `groups/{groupId}`、`groups/{groupId}/members/{uid}`、作成者の `users/{uid}.groupId` をatomic writeで整合させる。
- 参加・退出・所有者移譲はFirestore Transactionで実装する。クライアントの事前readだけを根拠に人数を判定しない。
- メンバー一覧は `groups/{groupId}/members` の一つのsnapshot listenerで取得する。profileをメンバーごとに読むN+1を作らず、member documentに必要最小限の表示名snapshotを持たせる。
- 招待tokenは平文でFirestoreに保存しない。十分な乱数tokenのSHA-256のみを `groupInvites` に保存する。期限・revoke・使用済みを検証する。
- Phase 1で保護した `users/{uid}` の `groupId` を、group create/join/leaveの必要な遷移だけにRulesで拡張する。users collectionのlistは許可しない。
- Firestore Rulesだけで表現できないtransaction整合性はクライアントtrust boundaryとして明記し、MVPではCloud Functionsへ依存しない。

## 実装対象

```text
lib/features/group/
  domain/
  application/
  infrastructure/
  presentation/
lib/app/router.dart
lib/app/providers.dart
firestore.rules
firebase/rules-tests/src/groups.test.js
test/features/group/
integration_test/group_flow_test.dart
```

画面はGroup Onboarding、Create、Join、Dashboard、Invite、Member listを最小限で実装する。認証済みユーザーで `groupId == null` ならOnboarding、所属済みならDashboardへ遷移する。Android Native実装はない。

## 完了条件

- Aがgroupを作成し、Bが有効tokenで参加できる。
- 両端末のmember listがリアルタイム更新される。
- 二つ目のgroup参加、41人目、期限切れ・revoke済み招待を拒否する。
- ownerが退出する前に移譲導線を提供し、最後のmemberの退出仕様を明示する。
- dashboard初回readはgroup document + members queryを基本とし、N+1 profile readを発生させない。
- Flutter unit/widget test、Firestore Emulator Rules test、2クライアントintegration test、`flutter build apk --debug` が成功する。

## 推奨commit分割

1. `feat: groupドメインとFirestore repositoryを追加`
2. `feat: group作成と参加を実装`
3. `feat: member一覧と招待管理を実装`
4. `feat: owner移譲と退出制約を実装`
5. `test: group transactionとRulesを検証`
6. `docs: Group実装手順を更新`

作業完了時は、branch、commit、Firestore schema/Rules/Index、テストの実行結果、既知のtrust boundary、PR作成コマンドを報告する。
