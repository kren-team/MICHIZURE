# ADR 0003: Device Owner + setPackagesSuspendedでMVP封印を実現する

- Status: Accepted for hackathon MVP
- Date: 2026-07-26

## Context

Task failure後、ユーザー選択のSNS・ゲーム・動画アプリをDebt完済または期限まで実際に利用不能にする必要がある。通常のAndroid app permissionには他packageをsuspendする権限がない。ハッカソンはAndroid Emulatorを管理対象端末としてprovisionできる。

同時に、Task中にユーザーが別アプリをforegroundにした事実を検知しつつ、画面OFF、keyguard、permission dialog、着信を誤判定しない必要がある。

## Decision

- demo APKをDevice Policy Controllerとして実装し、fresh EmulatorのDevice Ownerへadb provisionする。
- lock対象はTask開始時snapshotする。
- failure時は`DevicePolicyManager.setPackagesSuspended`を使用する。
- foreign app検知はUsage Accessを得たForeground ServiceからUsageEvents `ACTIVITY_RESUMED`をpollする。
- Activity lifecycleはsupporting evidenceのみ。
- system interruption gateと600ms dwellで一時遷移を除外する。
- lock obligationをDebt ID別にnative localへ保存し、effective package unionをreconcileする。

## Why setPackagesSuspended

- suspended appはActivity開始、notification、recents、toast/dialog等が抑止され、要件の「利用不能」に最も直接対応する。
- package単位でapply/releaseでき、Debt別obligationのunionと相性がよい。
- APIが失敗package一覧を返すためpartial failureを診断できる。
- app dataを消さずに可逆である。

## Rejected alternatives

### Lock Task Mode

kioskとしてallowlist外への移動を最初から防ぐ。ユーザーが別アプリを開いてfailureになるプロダクト体験を成立させにくく、Task後の選択packageだけをDebt連動封印する方式にも合わない。

### `setApplicationHidden`

利用不能にはできるがlauncherから消え、インストールされていないように見える。可逆な「封印」の説明、partial failure、ユーザー診断に不利で効果が過剰。

### AccessibilityService

AccessibilityServiceは障害のあるユーザーの支援に使用すべきAPIである。単なる監視・封印に使用せず、Play policy上の迂回策にしない。

### Activity lifecycle only

自アプリのforeground喪失は分かるが、その理由や新しいpackageが分からない。system dialog、keyguard、callで誤判定する。

### ActivityManager tasks

API 21以降、第三者appには他appのrunning task情報が制限され、core logicへの利用も公式に非推奨。

### Overlay / VPN / notification

他packageを本当にsuspendせず、回避可能または目的外権限となる。

## Consequences

### Positive

- Emulatorで強制力のあるデモが可能。
- AccessibilityServiceを使わない。
- OS policyとDebtをreason別に安全に対応付けられる。
- failure直後にnetworkを待たずlockできる。

### Negative

- fresh / fully managed deviceが必要。
- 一般ユーザーの既存個人端末では利用できない。
- Usage Accessは別途ユーザー許可が必要。
- 一部system packageはsuspend不可。
- FGS、package visibility、DPCにPlay / Enterprise審査が必要。
- UsageEventsだけではユーザー意図を完全に判定できない。

## Public product decision

一般公開時は次のどちらかを新ADRで選ぶ。

1. consumer版: hard lockを削除しadvisory penaltyへ縮退
2. enterprise版: 正式なAndroid Enterprise DPC / EMMとして提供

通常権限で同じhard lockを提供できるという仮定は禁止する。

## References

- [Suspend packages](https://developer.android.com/reference/android/app/admin/DevicePolicyManager#setPackagesSuspended(android.content.ComponentName,%20java.lang.String%5B%5D,%20boolean))
- [Provision a fully managed test device](https://developer.android.com/work/guide#fully_managed_device)
- [UsageStatsManager permission](https://developer.android.com/reference/android/app/usage/UsageStatsManager)
- [Lock task mode](https://developer.android.com/work/dpc/dedicated-devices/lock-task-mode)
