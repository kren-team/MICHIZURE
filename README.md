# MICHIZURE

約束した集中タスクからユーザー操作で離脱すると、選択したAndroidアプリを一時的に封印し、所属グループにスクワット負債を発生させるAndroid向けプロダクトです。グループは端末上のスクワット判定を使って共同返済します。

現在は設計フェーズです。FlutterアプリやFirebase環境はまだ生成していません。実装は `dev` から機能ブランチを作成し、[implementation-plan.md](docs/implementation-plan.md) の順序で進めます。

## 設計上の重要な結論

- ハッカソンMVPは、管理対象のAndroid Emulatorを Device Owner としてプロビジョニングする。
- 封印は Kotlin から `DevicePolicyManager.setPackagesSuspended` を使用する。
- タスク離脱検知は、Foreground Service が `UsageStatsManager` の `ACTIVITY_RESUMED` を監視し、画面OFF・Keyguard・既知のシステム割り込みを除外する。
- 一般ユーザー向けの通常権限アプリでは、任意の他アプリを強制的に封印できない。公開版は「Android Enterprise管理端末版」または「強制封印を持たないコンシューマー版」に分ける。
- UI、ユースケース、Firestore連携は Flutter / Dart、Device Owner、UsageStats、CameraX、ML Kit は Kotlin が担当する。
- バックエンドは Firebase Authentication と Cloud Firestore のクライアントSDKのみを必須とし、MVPは Spark Plan で動かす。
- スクワット映像は保存・外部送信せず、CameraX + ML Kit Pose Detection + 状態機械で端末内判定する。

## ドキュメント

最初に以下を順番に読んでください。

1. [プロダクト要件とMVPスコープ](docs/product-requirements.md)
2. [システムアーキテクチャ](docs/architecture.md)
3. [画面・状態遷移](docs/screen-flow.md)
4. [Firestoreデータモデル](docs/data-model.md)
5. [Firestore Rules設計](docs/firestore-rules-design.md)
6. [Android封印・離脱検知](docs/android-enforcement.md)
7. [スクワット判定](docs/squat-detection.md)
8. [Flutter状態管理](docs/state-management.md)
9. [セキュリティとプライバシー](docs/security-privacy.md)
10. [テスト戦略](docs/testing.md)
11. [実装計画](docs/implementation-plan.md)
12. [Emulatorデモ計画](docs/demo-plan.md)
13. [コスト見積もり](docs/cost-estimation.md)
14. [次の1ブランチの作業](NEXT_TASK.md)

技術判断の理由は [ADR一覧](docs/adr/) にあります。後続Agentは作業前に [AGENTS.md](AGENTS.md) も必ず読んでください。

## ブランチ戦略

```text
main
└── dev
    ├── chore/*
    └── feature/*
```

- `main`: リリース可能な状態のみ
- `dev`: 機能ブランチの統合先
- `feature/*`: 機能実装
- `chore/*`: 環境構築・ドキュメント・保守

`main` と `dev` へ直接機能コミットを行いません。force pushと既存コミットの書き換えは禁止です。

## 実装開始時の予定構成

```text
lib/
  core/
  features/
    auth/
    group/
    task/
    enforcement/
    debt/
    squat/
android/app/src/main/kotlin/com/kren/michizure/
firebase/
test/
integration_test/
```

実際の生成対象と依存関係は [NEXT_TASK.md](NEXT_TASK.md) に限定してあります。
