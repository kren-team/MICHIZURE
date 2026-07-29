# NEXT TASK: Phase 11 `feature/demo-polish`

## 目的

Phase 0〜10で完成した業務機能とRecovery基盤を変更せず、2 Emulatorで再現可能なハッカソンデモ、診断、visual polishを仕上げる。

新しいTask / Debt / Contribution semantics、Android enforcement方式、Squat threshold、Firestore schemaを変更しない。

## Branch

```bash
git fetch origin
git switch dev
git pull --ff-only origin dev
git switch -c feature/demo-polish
```

## 最初に読む

1. `AGENTS.md`
2. `README.md`
3. `docs/demo-plan.md`
4. `docs/recovery-reconciliation.md`
5. `docs/architecture.md`
6. `docs/android-enforcement.md`
7. `docs/squat-detection.md`
8. `docs/security-privacy.md`
9. `docs/testing.md`
10. `docs/implementation-plan.md`
11. 関連ADR

## In scope

- deterministic demo target / seed / reset runbook
- 2 EmulatorのA/Bデモ手順とpreflight診断
- Home、Task、Debt、Squat、Recovery状態の最小visual polish
- demo用app icon / labels / empty state
- Camera feedback / latency表示のデモ向け改善
- release buildにdebug fake route / commandが含まれない検証
- Phase 0〜10 E2E、process kill / reboot回帰、当日runbook

## Out of scope

- 新しい業務機能
- Firestore schema / Rulesの再設計
- Device Owner方式の変更
- Camera画像・landmarkの保存または送信
- AccessibilityService
- Cloud Functions必須化

## 必須不変条件

- debug synthetic inputをProduction dataとして偽装しない。
- release buildへFakeSquatDetector、debug-only package visibility、Emulator fallbackを混入させない。
- Device Owner Emulatorをwipe / data clearしない手順を標準とする。
- package一覧、UsageEvents、Camera / pose dataを端末外へ送信しない。
- Phase 10 Recoveryと既存テストを弱体化しない。

## Acceptance Criteria

- AのTask failureからBのSquat返済、Aのunlockまでを再現可能なrunbookで完走できる。
- demo前preflightでFirebase Emulator、Auth、Device Owner、Usage Access、notification、camera、選択packageを診断できる。
- process kill / reboot後もPhase 10の保証どおり収束する。
- debug / release境界をautomated testで確認する。
- 主要画面がデモ観客に状態と次操作を説明できる。

## Tests

- Phase 0〜10全回帰
- 2 client Firebase Emulator E2E
- managed Emulator instrumentation
- debug / release manifest・dependency・fake source境界
- process kill / reboot smoke
- latency計測と当日リハーサル

## 停止条件

Phase 11完了後は新Phaseを推測して開始せず、最終デモ readinessを報告して停止する。
