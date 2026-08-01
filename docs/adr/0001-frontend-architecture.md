# ADR 0001: Flutter feature-first architectureとRiverpodを採用する

- Status: Accepted
- Date: 2026-07-26

## Context

Flutter UI、Firestore stream、Kotlin platform event、再起動復元を短期間で統合しつつ、後続Coding Agentが機能単位で並行実装できる境界が必要である。Presentation / Application / Domain / Infrastructureの分離要件がある一方、全CRUDへのUseCase追加はハッカソンに過剰である。

## Decision

- feature-firstの下に4層を置く。
- Riverpodを状態管理とDIに使用する。
- generatorを使わずmanual providerから開始する。
- navigationは`go_router`を使用する。
- Domainにrepository interfaceと純粋state machineを置く。
- 複数Repository、native、outboxをまたぐ処理だけApplication UseCaseにする。
- FirestoreとPlatform ChannelはInfrastructure adapterに閉じ込める。

## Consequences

### Positive

- Repository、Clock、SquatDetector、DeviceControlをテストで差し替えやすい。
- feature branchのファイル競合を減らせる。
- Firestore/Kotlinの型がWidgetへ漏れない。
- fake pose sourceとproduction on-device pose engineを同じportで扱える。

### Negative

- 小規模な画面にも一定のファイル分割が生じる。
- RiverpodとDomain streamの責務を曖昧にすると二重状態になる。
- manual providerは依存graphの記述量が増える。

## Rejected alternatives

- Provider / ChangeNotifierのみ: 十分実現可能だが、非同期stream、override、複数状態の表現でRiverpodの方が一貫する。
- BLoC: event/state boilerplateがMVP規模に重い。
- Redux: 端末serviceやFirestore streamまで単一storeへ集約すると責務が肥大化する。
- 全機能Clean Architectureテンプレート: 空のUseCase/DTOを量産するため不採用。

## Guardrails

- state managementライブラリを追加併用しない。
- architecture変更は新ADRと移行計画を必要とする。
- Providerをグローバルmutable cacheの代替にしない。

## References

- [Flutter architecture guide](https://docs.flutter.dev/app-architecture/guide)
- [Flutter architecture recommendations](https://docs.flutter.dev/app-architecture/recommendations)
