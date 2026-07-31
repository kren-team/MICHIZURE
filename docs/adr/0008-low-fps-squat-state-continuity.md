# ADR 0008: 低FPSでは速度を失効し、Pose loss時だけスクワット状態を破棄する

- Status: Accepted
- Date: 2026-07-31
- Supersedes: [ADR 0007](0007-knee-angle-hip-drop-squat.md) のframe gap、calibration、過深動作、Preview FPS選択

## Context

実Cameraではlandmarkが追従していても、33〜59 frameのskipと700〜1,674msのstallが観測された。実装は有効sample間隔が250msを超えただけでFSMとcalibrationを全resetし、invalid poseも250msで同様にresetしていた。このため低く不規則なcallback FPSでは、`CALIBRATING`完了や進行中phaseの維持が困難だった。

## Decision

- callback gapとusable pose lossを別の状態として扱う。
- valid sample間隔が400msを超えた場合はvelocityとOne-Euroの微分履歴だけを失効し、calibration baselineとFSM phaseは維持する。
- usable poseが1,500msを超えて失われた場合だけ、進行中repを破棄して`CALIBRATING`へ戻す。
- duplicate / reversed timestampは従来どおりrejectし、phase確認は連続frame数でなくmonotonic durationをauthorityにする。
- calibrationは2秒の観測期間・6〜8 valid sampleを使い、medianとmedian absolute deviationからstanding knee angle、hip Y、leg scale、jitter、sideを求める。3秒で成立しなければ再試行する。
- BOTTOMはknee angle 120°以下かつnormalized hip drop 0.20以上を150ms確認する。必要深度より深い動作も、正順のphaseと直立復帰を満たせば有効とする。
- Preview FPSはactive cameraが報告したrangeから選び、未対応rangeを強制しない。ImageAnalysis上限は物理GPU 12、物理CPU 8、Emulator CPU 6 FPSとする。
- debug diagnosticsはraw / filtered angle、phase遷移理由、reset理由、confirmation時間、calibration数、input / submit / callback / valid-pose FPSを最大4 FPSで送る。画像・landmarkは送らない。

## Consequences

- 単一の長いcallback遅延でスクワット途中のphaseを失わず、次のvalid sampleから位置・角度中心で再開できる。
- 1,500ms未満の遮蔽中に起きた動作そのものは観測できないため、未観測phaseを推測してcountしない。各phaseの観測条件は引き続き必要である。
- 深い動作の安全性評価は本MVPの姿勢検出だけでは保証できない。警告は可能だが、深さだけを罰的にrejectする仕様にはしない。
- 実効FPSとlatencyの達成はhost webcamまたは物理端末で別途manual gateとし、synthetic testから推測しない。

## References

- [ADR 0007](0007-knee-angle-hip-drop-squat.md)
- [CameraX frame-rate API](https://developer.android.com/reference/androidx/camera/core/Preview.Builder#setTargetFrameRate(android.util.Range%3Cjava.lang.Integer%3E))
- [MediaPipe ImageProcessingOptions](https://ai.google.dev/edge/api/mediapipe/java/com/google/mediapipe/tasks/vision/core/ImageProcessingOptions)
