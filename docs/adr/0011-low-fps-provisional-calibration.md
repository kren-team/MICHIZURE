# ADR 0011: 非連続sampleと暫定baselineで低FPS Calibrationを完了する

- Status: Accepted
- Date: 2026-08-01
- Amends: [ADR 0010](0010-multi-evidence-low-resolution-squat.md) のCalibration入口と立位復帰

## Context

実Cameraでは膝角度171〜180°の直立sampleが得られていた一方、約2 FPS、一時的な`lowerBodyConfidenceLow` / `lowerBodyTooSmall`、腰位置と膝角度のjitterにより、6〜8 sample・2秒観測・3秒timeoutのCalibrationが完了しなかった。候補のhip/knee spreadが閾値を超えると`REJECT_CALIBRATION_MOTION`になり、timeoutとside変更は蓄積済み候補を全消去したため、FSMは全期間`CALIBRATING`に留まった。

## Decision

- 直立候補は8秒windowへ非連続に最大8件蓄積し、2件をminimum、3件をpreferredとする。160°以上をstrong、150°以上の幾何学的に妥当なsampleをauxiliaryとし、上位sampleのmedianをbaselineにする。
- 1件の165°以上をprovisionalとして保持し、そこから20°以上下降したsampleを得た場合はbaselineを確定して同じsampleからattemptを開始する。
- invalid pose、confidence/size不足、単一motion outlier、400ms超gap、side違いは該当sampleだけを無視し、候補を消去しない。環境別pose-loss timeoutを超えた場合だけ候補とattemptを破棄する。
- 通常qualityは3点すべて0.65以上とleg scale 0.22以上を維持する。Calibrationだけ、同一側3点がfinite・許容bounds内・角度計算可能で、少なくとも2点が0.22以上ならconfidence fallbackを許可する。小さい人物も160°以上の直立幾何が成立する場合だけsize fallbackを許可する。
- Calibration timeoutはphysical 8秒、Emulator 12秒とする。strong candidateがあればprovisional確定、auxiliaryだけならwindowを延長し、候補0件だけを完全resetする。
- 立位復帰は`knee >= S-25°`、または`knee >=155°`かつattempt最小角度から30°以上回復をstrong 1 sampleとして受け付ける。BOTTOM、valid pose、duration、refractory、attempt identityは引き続き必須とする。

## Consequences

- 約2 FPSでquality failureを挟んでもCalibrationを開始でき、Calibration中に始まった最初のスクワットを捨てない。
- fallback sampleはCalibration専用であり、通常trackingやrep復帰を低confidenceのまま許可しない。
- 立位候補なし、15°未満の揺れ、BOTTOM未到達、立位未復帰、duration外、duplicate / bounceはcountしない。
- Camera frame、landmark、Preview、ImageAnalysis、MediaPipe model、Contribution / Firestore契約は変更しない。

## Rejected alternatives

- Production全体のconfidenceを0.22へ下げる: 追跡中の誤検出を増やすためCalibration専用fallbackへ限定した。
- timeoutごとに全候補を消す: 低FPSで同じ失敗を繰り返すためsoft timeoutにした。
- 2件が揃うまで下降sampleを捨てる: 今回の実Camera系列を失うためprovisional baselineからattemptへ引き継ぐ。
