# ADR 0009: Calibration相対深度と低FPS phase skipでスクワットを数える

- Status: Accepted
- Date: 2026-07-31
- Amends: [ADR 0008](0008-low-fps-squat-state-continuity.md) の固定BOTTOM閾値と全phase観測

## Context

実Cameraではhip / knee / ankleとoverlayが脚へ追従していても、2D膝角度の最小値が130〜145°程度となり得る。従来のProduction FSMは膝角度120°以下とnormalized hip drop 0.20以上を同時に要求し、さらに固定ROM 50°、最大hip drop 0.18、DESCENDING / BOTTOM / ASCENDINGの明示観測を受入条件にしていた。そのため本人の通常スクワットがCalibrationに成功してもBOTTOMへ到達せず、低FPSでは中間phaseをframeごと失ってrepが0のままになった。

## Decision

- 6〜8件の安定立位sampleのmedianをstanding knee angle `S`とする。
- `standingEnter=S-12°`、`descendingStart=S-20°`、`bottom=S-35°`、`returnStanding=S-15°`をsessionごとに導出し、それぞれ安全範囲へclampする。BOTTOMは125〜140°へclampする。
- BOTTOMは`knee<=bottom`かつ`hipDrop>=0.10`とする。さらに`knee<=bottom-8°`なら`hipDrop>=0.06`を許可し、125ms確認する。
- `bottomReached=true`、立位復帰200ms、全体800〜6,000ms、refractory、未加算sequenceをrep acceptanceとする。固定ROM 50°とhip drop 0.18を追加のacceptance gateにしない。
- 深い動作はwarningにできるが、深いことだけではrejectしない。
- 低FPSでは`STANDING→BOTTOM`、`DESCENDING→BOTTOM`、`BOTTOM→STANDING/REP_ACCEPT`を許可する。DESCENDING / ASCENDINGを各1 frame以上観測することは必須にしない。
- 400ms超のvalid frame gapはvelocityとOne-Euro微分履歴だけを失効させ、phaseと`bottomReached`を維持する。usable pose lossが1,500msを超えた場合だけattemptを破棄してCALIBRATINGへ戻す。
- debug diagnosticsはCalibration baseline、4 threshold、attempt min/max、前後phase、condition reason、confirmation durationを最大4 FPSで表示する。

## Consequences

- カメラ角度により直立角度が異なるユーザーでも、本人の立位に対する35°の屈曲を初期BOTTOM基準にできる。
- 低FPSで中間phaseを取り逃しても、観測済みBOTTOMと立位復帰からrepを確定できる。
- 浅い屈伸、前屈、BOTTOM未到達、立位未復帰、pose loss、duplicate / bounceは引き続き拒否する。
- 2D poseのprecisionは撮影条件に依存するため、synthetic testだけで実Camera成功を主張せず、Squat Lab manual gateを残す。
- MediaPipe model、Camera Preview / overlay、Firestore、Contribution identityは変更しない。

## Rejected alternatives

- 固定120°だけを135°へ緩和: 個人の直立角度差を扱えず、原因を別の固定値へ移すだけになる。
- angleだけ、またはhip dropだけでBOTTOM判定: 浅い膝曲げや前屈のfalse positiveが増えるため採用しない。
- 欠落したBOTTOMを速度から推測: callback gap中の未観測動作を推測してcountするため採用しない。BOTTOM候補の時間確認は維持する。
