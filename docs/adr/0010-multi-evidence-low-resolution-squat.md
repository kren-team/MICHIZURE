# ADR 0010: 低解像度解析と複数evidence経路で低FPSスクワットを判定する

- Status: Accepted
- Date: 2026-08-01
- Amends: [ADR 0009](0009-calibrated-relative-squat-depth.md) のBOTTOM同時条件、確認時間、立位復帰、pose-loss境界
- Amended by: [ADR 0011](0011-low-fps-provisional-calibration.md) のCalibration fallbackと立位復帰

## Context

実Cameraでlandmarkとoverlayが脚へ追従しても、Emulator CPUでは高解像度のPose解析により有効sampleが疎になる。またADR 0009のBOTTOMは相対膝角度、hip drop、125ms確認を同時に要求するため、片方の2D signalが弱い通常スクワットやBOTTOM付近を1 frameしか取得できない動作を取りこぼす。

## Decision

- Previewの設定は変えず、ImageAnalysisだけ320×240を最優先にする。未対応時は256×192、320×180、近傍の低解像度4:3、640×480、残りのsupported sizeへfallbackする。
- attempt内にcalibrated standing angle、最小膝角度、最大hip drop、下降/上昇観測、score、成立経路を保持する。
- BOTTOM経路Aはknee bend 24°以上、または`knee<=clamp(S-24°,135°,150°)`とし、hip dropを要求しない。
- 経路Bはknee bend 16°以上かつhip drop 0.04以上とする。
- 経路Cはhip drop 0.08以上、下降後の上昇反転、knee bend 8°以上とする。
- knee evidenceはstrong / medium / minimumを3 / 2 / 1、hip evidenceはstrong / mediumを3 / 2、反転を2とする。同一signalを重複加点せず、score 3以上かつ実変化とA/B/Cのいずれかを満たした場合だけ`bottomReached=true`にする。
- BOTTOMの連続保持を必須にしない。強い1 sampleまたはattempt extremaから確定し、STANDING→BOTTOM、DESCENDING→BOTTOM、BOTTOM→STANDING/REP_ACCEPTを許可する。
- standingは`knee>=S-25°`、または`knee>=S-32° && hipDrop<=0.15`。returnは`knee>=S-28°`、または`knee>=S-35° && hipDrop<=0.18 && upwardObserved`を100ms確認する。低FPSのstrong returnは1 sampleを許可する。
- 400ms超のvalid frame gapではvelocityだけを無効化し、phase、bottomReached、attempt extremaを維持する。usable pose lossがEmulator 4,000ms / physical 2,000msを超えた場合にattemptを破棄して再Calibrationする。
- Analyzer入口のtimestamp / busy / FPS gateを`toBitmap()`より前に置き、Emulator 4 FPS、physical CPU 8 FPS、physical GPU 10 FPSに制限する。MediaPipe callbackまではsingle in-flightとし、drop frameではBitmap / MPImageを生成しない。
- requested / actual analysis resolution、attempt evidence、成立経路を最大4 FPSのdebug diagnosticsへ追加する。

## Consequences

- 膝角度またはhip dropの一方が弱くても、別の独立signalや反転を伴う動作を低FPSで認識できる。
- hip dropだけの前屈は、経路Cの最低10°膝曲げを満たさないためcountしない。
- 解析pixel数は従来requestの480×640から320×240で4分の1になる。actual sizeとlatencyは端末依存なのでSquat Labで記録する。
- MediaPipe model、Preview / overlay transform、selected side、Contribution identity、Firestore、画像非保存・非送信方針は変更しない。
- synthetic testは状態機械の決定性を示すが、実人体の精度・FPS・latency成功を示さない。manual gateは別途必須である。

## Rejected alternatives

- すべての閾値を一律に緩める: false positiveの原因を分離できないため採用しない。
- hip dropだけでBOTTOMにする: 前屈をcountするため採用しない。
- Previewも320×240へ固定する: 解析負荷削減に不要で、表示品質とguide確認を悪化させるため採用しない。
- frame gapごとにattemptを破棄する: Emulatorの疎なcallbackだけで正常動作を失うため採用しない。
