# ADR 0004: CameraX + ML Kitの端末内状態機械でスクワットを数える

- Status: Accepted
- Date: 2026-07-26

## Context

実際のスクワットをp95 500ms以内で数え、カメラ画像・動画を保存またはサーバー送信せず、ほぼ無料で動作させる必要がある。単純なframe countでは1動作を何十回も数えるため、時系列の姿勢解釈が必要である。

## Decision

- CameraX Preview + ImageAnalysisをKotlinで実装する。
- ML Kit Pose Detection base SDKのSTREAM_MODEで33 landmarksを取得する。
- 膝角度、股関節角度、normalized hip drop、velocity、confidenceを抽出する。
- median + EMAで平滑化する。
- `STANDING → DESCENDING → BOTTOM → ASCENDING → STANDING`を完走した時だけ1repとする。
- hysteresis、minimum phase / rep duration、range of motion、refractory periodを設ける。
- frame / landmarksをDartへ送らず、state / rep eventだけEventChannelへ送る。
- release buildはML Kit pathだけ、debug buildにはDI可能なsynthetic / fake sourceを置く。

## Why ML Kit only

- full-body 33 landmarksとin-frame likelihoodを端末内で得られる。
- base SDK / stream modeはリアルタイム用途向け。
- 画像upload、server inference、API costが不要。
- threshold state machineはスクワットという限定動作に説明可能でtest可能。

## Why not OpenAI API

- カメラ画像を外部送信しない要件に反する。
- network latencyで500ms SLOが不安定。
- per-frameまたはclipの継続費用が発生。
- offlineで動かない。
- ML Kitで必要なlandmarkが得られるため追加価値がない。

## Rejected alternatives

- frameごとのpose / knee bend count: 二重countする。
- Flutter camera frameをDartでML処理: platform copyとplugin依存を増やす。
- accurate ML Kit SDKを最初から採用: Emulator latencyリスク。baseで精度不足を計測してから比較する。
- server-side custom model: privacy、cost、offline要件に不適。
- prerecorded videoを本番source化: codec / pipeline複雑性とprivacy surfaceが増える。

## Consequences

### Positive

- privacyと低運用費を満たす。
- 状態機械を合成landmarkで決定的にunit testできる。
- CameraX backpressureで古いframeを捨て低遅延を保てる。
- fake sourceがFirestore / UI demoをcamera環境から分離する。

### Negative

- threshold tuningが体格、camera angle、服装、照明に影響される。
- ML Kit APIはbeta。
- client判定をcloud側が真正性検証できない。
- 2D featureでは類似動作を完全に排除できない。

## Revisit criteria

- representative testでrep precision / recallが合意閾値に届かない
- p95 inferenceが500ms budgetを超える
- ML Kit betaにbreaking change / deprecation
- 複数camera angleやaccessibility要件の追加

再検討順:

1. thresholds / calibration / normalized feature改善
2. accurate SDK A/B
3. on-device TFLite classifier
4. privacy要件変更が承認された場合のみserver案

## References

- [ML Kit pose detection](https://developers.google.com/ml-kit/vision/pose-detection)
- [Detect poses on Android](https://developers.google.com/ml-kit/vision/pose-detection/android)
- [CameraX ImageAnalysis](https://developer.android.com/media/camera/camerax/analyze)
