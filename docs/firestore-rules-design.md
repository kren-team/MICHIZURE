# Firestore Security Rules設計

## 1. 目的と限界

Rulesの目的は、認証・所属・field schema・状態遷移・atomic invariantを強制することである。Rulesはclient codeが本物のML Kitを実行したこと、ユーザーが実際にスクワットしたこと、端末が本当にアプリを封印したことを証明できない。

MVPは次を守る。

- default deny
- userは自分のprivate profileだけを直接読める
- group dataはmemberだけが読める
- 最大40人、単一group、1 active Taskをatomicに守る
- 1 failure = 1 Debt、`totalReps = memberCount × 10`
- 1 immutable event = 1 rep
- Debt / member aggregate / eventを同一transactionで更新
- `completedReps <= totalReps`
- deadline後のContributionを拒否
- package inventory、画像、任意fieldの書き込みを拒否

## 2. Rules versionと共通helper

実装は `rules_version = '2';` を使用する。以下は設計擬似コードであり、Phase 0以降にEmulatorへcompileし、Rules Testで確定する。

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    function signedIn() {
      return request.auth != null;
    }

    function isSelf(uid) {
      return signedIn() && request.auth.uid == uid;
    }

    function userPath(uid) {
      return /databases/$(database)/documents/users/$(uid);
    }

    function memberPath(groupId, uid) {
      return /databases/$(database)/documents/groups/$(groupId)/members/$(uid);
    }

    function isMember(groupId) {
      return signedIn() && exists(memberPath(groupId, request.auth.uid));
    }

    function isOwner(groupId) {
      return isMember(groupId)
        && get(memberPath(groupId, request.auth.uid)).data.role == "owner";
    }

    function onlyChanged(fields) {
      return request.resource.data.diff(resource.data).affectedKeys().hasOnly(fields);
    }

    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

helper nestingとdocument access callはRules制限内に保つ。transaction / batch全体は20 access calls、各operationは10 callsが上限である。Emulatorのrules coverageで実測する。

## 3. QueryはRulesのfilterではない

Rulesが `resource.data.groupId` のmembershipを要求する場合、client queryも必ず現在の `groupId` で制約する。

許可する例:

```text
debts
where groupId == users/{uid}.groupId
where status == "active"
orderBy lockExpiresAt asc
limit 20
```

禁止する例:

```text
debts
where status == "active"
```

後者は「返却後にRulesで他groupを除外」されず、query全体が拒否される。`limit`は認可条件ではないがread cost制御として必須。

## 4. `users/{uid}`

### Read

- 本人だけget/listを許可し、他人のusers docは読ませない。
- member displayはgroup member snapshotを使用する。

### Create

- `isSelf(uid)`
- field keys完全一致
- `groupId == null`
- `activeTaskSessionId == null`
- displayNameはtrim済みの正規形、1〜40 Unicode文字で、前後空白・制御文字・改行なし
- `createdAt == request.time`, `updatedAt == request.time`
- schemaVersion 1

### Update

3経路をORで分離する。

1. profile update
   - `displayName`, `photoUrl`, `updatedAt`だけ
   - 自分のmember docがある場合は同じbatchでdisplayNameSnapshotも更新
2. group pointer update
   - `groupId`, `updatedAt`だけ
   - joinならafter-stateに自分のmember docが存在しgroup countが+1
   - leaveならafter-stateにmember docが存在せずgroup countが-1
3. active Task pointer update
   - `activeTaskSessionId`, `updatedAt`だけ
   - null→taskIdならafter-stateのTaskが自分のrunning
   - taskId→nullならafter-stateのTaskが自分のterminal

### Devices subcollection

`users/{uid}/devices/{deviceId}`は本人だけがget/list/create/update/deleteできる。client writeは`token`, `platform=android`, `updatedAt=request.time`, `enabled`のexact fieldだけを許可し、他ユーザーのtoken取得を拒否する。通知APIのAdmin SDKはRules外のtrusted pathとしてgroup membershipを再検証する。

clientが任意にgroupIdやactiveTaskSessionIdを書き換える単独updateは拒否する。

## 5. `groups/{groupId}` とmembers

### Group create

- `ownerUid == auth.uid`
- `memberCount == 1`
- after-stateでowner member docが存在
- after-stateでuser.groupIdがgroupId
- name 1〜50文字
- timestamp / schema field一致

### Group read

- current memberのみ。
- join前のgroup名はInvite snapshotから読む。

### Group update

経路:

- metadata: ownerだけ、`name`, `updatedAt`
- join: memberCountが正確に+1、before < 40、after-stateでjoining userのuser/memberが整合
- leave: memberCountが正確に-1、after >= 1、after-stateでleaving userのuser/memberが整合
- owner transfer: `ownerUid`変更とold/new member role変更がatomic

Rulesから「どの第三者がjoinしたか」をgroup update単体で一般化すると複雑になる。MVP joinは参加ユーザー自身のtransactionだけ許可し、after member pathを `request.auth.uid` に固定する。自分以外を追加・削除できない。

### Member

- list/get: group member
- create: document ID / `userId == auth.uid`、join workflowのみ
  - `displayNameSnapshot` はafter-stateの本人 `users/{uid}.displayName` と一致
  - join時は `inviteTokenHash` が有効なinvite documentを指す
  - owner作成時の `inviteTokenHash` はnull
- update:
  - 本人のdisplayNameSnapshot同期
  - owner transfer時のrole変更
- delete: 本人のleave workflowのみ
- owner member deleteはtransferが同じtransactionにない限り拒否

## 6. `groupInvites/{tokenHash}`

- `get`: signed-in userに許可
- `list`: 常に拒否
- create: group member、`createdByUid == auth.uid`、raw token fieldが存在しない、期限がrequest.timeより後かつ最大7日
- update: creatorまたはgroup ownerによる `revokedAt` 設定のみ
- delete: MVPは拒否
- join時は `revokedAt == null` かつ `request.time < expiresAt`

tokenHash doc IDは十分なentropyを持つraw tokenのSHA-256であり、短い人間入力コードを直接IDにしない。

join clientはinviteと自分のuserだけをtransaction readし、groupにはatomic incrementを書き込む。Rulesはgroupのbefore/afterが正確に+1かつ40以下であること、同じatomic write後にuser/memberが整合すること、memberの `inviteTokenHash` が未失効inviteを指すことを検証する。これにより非memberへgroup readを開放せず、同一userの複数group参加と41人目を拒否する。

leaveではownerを拒否し、`users.activeTaskSessionId == null`、member削除、group countの正確な-1、user pointerのnull化を同じatomic writeで要求する。未解決lock obligationによる退出拒否は、Debt/lock documentが導入される後続PhaseでRules条件を追加する。

## 7. `taskSessions/{taskId}`

### Read

- owner本人だけ。
- group memberへTask内容を公開しない。Debtはfailed user IDだけを共有する。

### Create running

- `ownerUid == auth.uid`
- auth userのgroupIdとTask groupIdが一致しmembershipが存在
- userのbefore `activeTaskSessionId == null`
- userのafter `activeTaskSessionId == taskId`
- `status == running`
- terminal / failure fieldsはnull
- `durationSec` 60〜10,800
- `expectedEndAt == startedAt + durationSec`
- `startedAt` は `request.time ± 60秒`
- `serverRecordedAt == request.time`
- `lockDurationSec == 1800`
- field allowlist、string length、schema version

### Update succeeded

- owner本人
- before running、after succeeded
- `request.time >= expectedEndAt`
- after user pointer null
- failure/debt fields nullのまま
- immutable fields不変

### Update failed

- owner本人
- before running、after failed
- `endedAt` は `request.time ± 60秒`
- `failureReason`は`user_aborted`、`foreign_app_foreground`、`monitor_capability_lost`、`recovery_detected_violation`のいずれかで、non-empty `failureEventId`
- `debtId == taskId`
- after user pointer null
- after-state `debts/{taskId}` が存在しTask fieldと一致
- `groupMemberCountAtFailure` がDebt / current group countと一致

terminal Taskの再update/deleteは拒否する。同一failureのretryは既存stateをreadしてclient側no-opとする。`debug_demo`と未知のreasonは拒否する。Rulesはeventが本物のnative検知かを証明できないため、改変clientによるfailure生成はMVP trust boundaryである。

## 8. `debts/{debtId}`

### Read

- current group member
- または `failedUserId == auth.uid`。失敗ユーザーがgroupを退出できないルールにしているため通常はmember条件にも一致する。
- failure transactionの冪等性確認に限り、未作成の`debts/{taskId}`を同じTaskのownerがgetできる。無関係なmissing IDと未認証getは拒否する。

### Create

- `debtId == failedTaskSessionId`
- `failedUserId == auth.uid`
- after-state Taskが同じIDでfailed
- `groupId` がTaskとcurrent user groupに一致
- `memberCountAtFailure == current group.memberCount`
- `repsPerMember == 10`
- `totalReps == memberCountAtFailure * 10`
- `completedReps == 0`, `status == active`
- `createdAt == request.time`
- `lockExpiresAt == task.endedAt + task.lockDurationSec`
- aggregate / close fields初期値

Phase 7では同一group memberまたはfailed userのreadと、下記expiration updateを追加した。Phase 8ではContributionの3-document atomic writeだけを追加し、それ以外のDebt直接更新はdefault denyを維持する。

### Contribution update

Rules上のinvariant:

```text
before.status == active
request.time < before.lockExpiresAt
completedReps(after) == completedReps(before) + 1
completedReps(after) <= totalReps
immutable fields unchanged
lastContributionEventId points to a newly-created after-state event
after contribution summary for event.userId increments by exactly 1
status:
  after.completedReps == totalReps ? completed : active
closedAt:
  completed ? request.time : null
```

Debtへ `lastContributionEventId` を置くのはRulesが関連eventを特定するためで、UI queryには使わない。

### Expiration update

- current group memberまたはfailed user
- before active
- `request.time >= lockExpiresAt`
- `status == expired`, `closedAt == request.time`
- repsと全immutable field不変
- contribution eventを同時作成しない

`completed`, `expired` からのupdate/deleteは拒否する。

## 9. Contribution summary / event

### Summary read

- Debtのcurrent group member。
- Phase 7はdetail表示中だけ最大40件をread-only購読する。

### Summary create/update

- doc ID / userIdがauth.uid
- `totalReps` はbefore（不存在なら0）から正確に+1
- `lastEventId` に対応するeventがafter-stateに存在
- after-state Debtが同じevent IDで正確に+1
- `lastContributedAt == request.time`
- 同じユーザーの前回Contributionから最短750msを設ける案をRules Test / 実機計測後に有効化する

summary単独writeは拒否する。

### Event

- direct get: current group memberで、かつ自分のuid prefixを持つeventのみ。transactionのmissing/duplicate確認に使う
- list/query: 全員拒否。通常UIはeventを購読せずDebt aggregateとsummaryだけを読む
- createのみ、update/delete拒否
- doc IDのuid prefix、`userId == auth.uid`
- `acceptedReps == 1`
- `sequence >= 1`
- `detectorType == mlkit`。Productionの自由入力・fake eventを拒否
- `createdAt == request.time`
- after Debt / summaryの `lastEventId` がこのevent ID
- before event不存在

これでも改変clientは `mlkit` と名乗れるため真正性保証にはならない。MVPはSpark Planとclient transactionを優先したtrust boundaryとして明記し、Productionではattestationとtrusted backendを検討する。

## 10. Field validation

全writeで次を実施する。

- `keys().hasAll()` と `hasOnly()`、updateは`diff().affectedKeys().hasOnly()`
- string length、int範囲、enum allowlist
- timestampの順序
- immutable identity / foreign key
- server timestampは `request.time` と比較
- unknown field拒否
- mapを追加する場合はnested keysもallowlist

## 11. Rules Test必須matrix

| ケース | 期待 |
|---|---|
| unauthenticated read/write | deny |
| 他user profile read | deny |
| memberが自groupをquery | allow |
| memberが他groupをquery | deny |
| 41人目join | deny |
| 2つ目group join | deny |
| ownerの未移譲leave | deny |
| Task pointerなしのrunning Task create | deny |
| expectedEndAt改ざん | deny |
| success deadline前 | deny |
| failure Debtなし | deny |
| Debt totalがmemberCount×10以外 | deny |
| contribution event単独create | deny |
| Debtだけincrement | deny |
| summaryだけincrement | deny |
| 同一event再create | deny / client no-op |
| totalを超えるrep | deny |
| deadline以降のrep | deny |
| deadline前のexpire | deny |
| terminal Debt書換・削除 | deny |
| raw invite token保存 | deny |
| invite list query | deny |
| package名・画像field追加 | deny |

## 12. Deploy gate

Rules変更PRは以下を満たさない限りdevへmergeしない。

1. `firebase emulators:exec` でRules Test全件成功
2. deny testをallow test以上に用意
3. rules coverageで未評価branchを確認
4. required indexとの整合
5. production projectへdeployする差分をreview
6. broad allow (`if true`, blanket signed-in write) がないこと

## 13. 公式資料

- [Writing conditions for Security Rules](https://firebase.google.com/docs/firestore/security/rules-conditions)
- [Data validation for atomic operations](https://firebase.google.com/docs/firestore/manage-data/transactions#data_validation_for_atomic_operations)
- [Test Firestore Security Rules](https://firebase.google.com/docs/firestore/security/test-rules-emulator)
- [Securely query data](https://firebase.google.com/docs/firestore/security/rules-query)
