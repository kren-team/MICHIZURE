package com.kren.michizure.pose

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SquatStateMachineTest {
    private val config = SquatDetectorConfig()

    @Test
    fun poseLossTimeoutIsEnvironmentSpecific() {
        assertEquals(4_000L, config.poseLossResetMs(isEmulator = true))
        assertEquals(2_000L, config.poseLossResetMs(isEmulator = false))
    }

    @Test
    fun standingAngle168ProducesMultiEvidenceThresholds() {
        val thresholds = config.thresholdsFor(168.0)

        assertEquals(143.0, thresholds.standingEnterAngle, 0.001)
        assertEquals(136.0, thresholds.standingRelaxedAngle, 0.001)
        assertEquals(148.0, thresholds.descendingStartAngle, 0.001)
        assertEquals(144.0, thresholds.bottomAngle, 0.001)
        assertEquals(143.0, thresholds.returnStandingAngle, 0.001)
        assertEquals(133.0, thresholds.returnStandingRelaxedAngle, 0.001)
    }

    @Test
    fun standingAngle175KeepsBottomThresholdInsideClamp() {
        val bottom = config.thresholdsFor(175.0).bottomAngle

        assertEquals(150.0, bottom, 0.001)
        assertTrue(bottom in 135.0..150.0)
    }

    @Test
    fun lowStandingAngleCannotProduceBottomThresholdBelow130() {
        val bottom = config.thresholdsFor(150.0).bottomAngle

        assertEquals(135.0, bottom, 0.001)
    }

    @Test
    fun kneeBendDeltaTwentyFourIsSufficientWithoutHipDrop() {
        val evidence = config.bottomEvidence(168.0, 144.0, 0.0, true, false)

        assertEquals(3, evidence.score)
        assertEquals(BottomEvidencePath.KNEE_ONLY, evidence.path)
    }

    @Test
    fun kneeBendDeltaSixteenAndHipDropPointZeroFourAreSufficient() {
        val evidence = config.bottomEvidence(168.0, 152.0, 0.04, true, false)

        assertEquals(4, evidence.score)
        assertEquals(BottomEvidencePath.KNEE_AND_HIP, evidence.path)
    }

    @Test
    fun hipDropAndReversalAreSufficientWithMinimumKneeBend() {
        val evidence = config.bottomEvidence(168.0, 160.0, 0.08, true, true)

        assertEquals(6, evidence.score)
        assertEquals(BottomEvidencePath.HIP_AND_REVERSAL, evidence.path)
    }

    @Test
    fun hipDropWithoutAnyKneeBendIsRejectedAsForwardBend() {
        val evidence = config.bottomEvidence(168.0, 168.0, 0.14, true, true)

        assertEquals(5, evidence.score)
        assertNull(evidence.path)
    }

    @Test
    fun eachEvidencePathCanSetBottomReachedInTheStateMachine() {
        val kneeOnly = calibratedDetector()
        val kneeUpdate = kneeOnly.valid(CALIBRATED_AT + 200, 144.0, 0.25)
        assertTrue(kneeUpdate.diagnostics.bottomReached)
        assertEquals(BottomEvidencePath.KNEE_ONLY, kneeUpdate.diagnostics.bottomEvidencePath)

        val kneeAndHip = calibratedDetector()
        val combinedUpdate = kneeAndHip.valid(CALIBRATED_AT + 200, 152.0, 0.27)
        assertTrue(combinedUpdate.diagnostics.bottomReached)
        assertEquals(
            BottomEvidencePath.KNEE_AND_HIP,
            combinedUpdate.diagnostics.bottomEvidencePath,
        )

        val hipReversal = calibratedDetector()
        hipReversal.valid(CALIBRATED_AT + 200, 160.0, 0.295)
        val reversalUpdate = hipReversal.valid(CALIBRATED_AT + 650, 160.0, 0.27)
        assertTrue(reversalUpdate.repCompleted)
        assertEquals(
            BottomEvidencePath.HIP_AND_REVERSAL,
            reversalUpdate.diagnostics.bottomEvidencePath,
        )
    }

    @Test
    fun kneeOnlyPathCountsWhenHipDropIsUnavailableAsEvidence() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        val updates =
            listOf(
                detector.valid(start, 150.0, 0.25),
                detector.valid(start + 300, 143.0, 0.25),
                detector.valid(start + 700, 132.0, 0.25),
                detector.valid(start + 1_100, 145.0, 0.25),
            )

        assertEquals(1, updates.count { it.repCompleted })
        assertEquals(BottomEvidencePath.KNEE_ONLY, updates.last().diagnostics.bottomEvidencePath)
    }

    @Test
    fun temporaryMissingKneeSamplePreservesHipReversalAttempt() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        detector.valid(start, 160.0, 0.295)
        val missingKnee = detector.invalid(start + 200)
        val returned = detector.valid(start + 500, 160.0, 0.270)

        assertEquals(SquatState.DESCENDING, missingKnee.state)
        assertEquals(1, returned.repSequence)
        assertTrue(returned.repCompleted)
        assertEquals(
            BottomEvidencePath.HIP_AND_REVERSAL,
            returned.diagnostics.bottomEvidencePath,
        )
    }

    @Test
    fun calibrationUsesTwoNonContiguousSamplesAndExposesBaseline() {
        val detector = calibratedDetector()
        val diagnostics = detector.valid(CALIBRATED_AT + 10, 168.0, 0.25).diagnostics

        assertEquals(SquatState.STANDING, detector.state)
        assertEquals("COMPLETE", diagnostics.calibrationStatus)
        assertEquals(168.0, diagnostics.calibratedStandingKneeAngleDeg!!, 0.001)
        assertEquals(0.25, diagnostics.baselineHipY!!, 0.001)
        assertEquals(0.50, diagnostics.legScale!!, 0.001)
        assertEquals(PoseSide.LEFT, diagnostics.calibrationSelectedSide)
    }

    @Test
    fun twoStandingSamplesCalibrateToTheirMedian() {
        val detector = SquatStateMachine(config)
        detector.valid(0, 171.1, 0.25)
        val completed = detector.valid(500, 176.7, 0.25)

        assertEquals(SquatState.STANDING, detector.state)
        assertEquals(173.9, completed.diagnostics.calibratedStandingKneeAngleDeg!!, 0.001)
        assertEquals("TWO_SAMPLE_MEDIAN", completed.diagnostics.standingBaselineSource)
        assertEquals("CALIBRATED_FROM_TWO_SAMPLES", completed.diagnostics.lastTransitionReason)
    }

    @Test
    fun invalidConfidenceAndTooSmallSamplesDoNotClearStandingCandidates() {
        listOf("poseNotDetected", "lowerBodyConfidenceLow", "lowerBodyTooSmall").forEach { reason ->
            val detector = SquatStateMachine(config)
            detector.valid(0, 171.1, 0.25)
            val interrupted = detector.invalid(500, reason)
            val completed = detector.valid(1_000, 176.7, 0.25)

            assertEquals(1, interrupted.diagnostics.calibrationSampleCount)
            assertTrue(interrupted.diagnostics.candidateBufferPreserved)
            assertEquals(SquatState.STANDING, detector.state)
            assertEquals(173.9, completed.diagnostics.calibratedStandingKneeAngleDeg!!, 0.001)
        }
    }

    @Test
    fun confidenceAndSizeFallbackSamplesAreCalibrationOnlyCandidates() {
        listOf(
            CalibrationQualityPath.ANGLE_CONFIDENCE_FALLBACK,
            CalibrationQualityPath.ANGLE_SIZE_FALLBACK,
        ).forEach { path ->
            val detector = SquatStateMachine(config)
            detector.calibrationCandidate(0, 176.7, path)
            val completed = detector.valid(500, 171.1, 0.25)

            assertEquals(SquatState.STANDING, detector.state)
            assertEquals(173.9, completed.diagnostics.calibratedStandingKneeAngleDeg!!, 0.001)
        }

        val tracking = calibratedDetector()
        val ignored =
            tracking.process(
                calibrationCandidateResult(
                    timestampMs = CALIBRATED_AT + 200,
                    knee = 120.0,
                    path = CalibrationQualityPath.ANGLE_CONFIDENCE_FALLBACK,
                ),
            )
        assertEquals(SquatState.STANDING, ignored.state)
        assertEquals(0, tracking.repSequence)
    }

    @Test
    fun calibrationCandidatesMustShareEightSecondWindow() {
        val detector = SquatStateMachine(config, isEmulator = true)
        detector.valid(0, 171.1, 0.25)
        detector.valid(3_000, 171.0, 0.25, side = PoseSide.RIGHT)
        detector.valid(6_000, 171.0, 0.25, side = PoseSide.RIGHT)
        val late = detector.valid(8_100, 176.7, 0.25)

        assertEquals(SquatState.CALIBRATING, detector.state)
        assertEquals(1, late.diagnostics.calibrationSampleCount)
    }

    @Test
    fun oneMotionOutlierDoesNotClearExistingCandidate() {
        val detector = SquatStateMachine(config)
        detector.valid(0, 155.0, 0.25)
        val motion = detector.valid(600, 155.0, 0.40)
        val completed = detector.valid(1_200, 171.0, 0.25)

        assertEquals("REJECT_CALIBRATION_MOTION", motion.diagnostics.lastCalibrationRejectReason)
        assertEquals(1, motion.diagnostics.calibrationSampleCount)
        assertTrue(motion.diagnostics.candidateBufferPreserved)
        assertEquals(SquatState.STANDING, detector.state)
        assertEquals(163.0, completed.diagnostics.calibratedStandingKneeAngleDeg!!, 0.001)
    }

    @Test
    fun provisionalStandingAutoCalibratesOnDescentAndCountsSameAttempt() {
        val detector = SquatStateMachine(config)
        val provisional = detector.valid(0, 176.7, 0.25)
        val bottom = detector.valid(500, 140.5, 0.30)
        val returned = detector.valid(1_000, 170.0, 0.25)

        assertEquals(176.7, provisional.diagnostics.provisionalStandingAngleDeg!!, 0.001)
        assertTrue(bottom.diagnostics.autoCalibratedOnDescent)
        assertEquals("AUTO_CALIBRATED_ON_DESCENT", bottom.diagnostics.standingBaselineSource)
        assertTrue(bottom.diagnostics.bottomReached)
        assertTrue(returned.repCompleted)
        assertEquals(1, returned.repSequence)
    }

    @Test
    fun calibrationCompletesAtTwoFpsAndAcrossThirteenHundredMillisecondGap() {
        val twoFps = SquatStateMachine(config)
        twoFps.valid(0, 171.1, 0.25)
        val twoFpsDone = twoFps.valid(500, 176.7, 0.25)
        val sparse = SquatStateMachine(config)
        sparse.valid(0, 171.1, 0.25)
        val sparseDone = sparse.valid(1_300, 176.7, 0.25)

        assertEquals(SquatState.STANDING, twoFpsDone.state)
        assertEquals(SquatState.STANDING, sparseDone.state)
    }

    @Test
    fun calibrationTimeoutUsesCandidateOrResetsOnlyWhenEmpty() {
        val withCandidate = SquatStateMachine(config)
        withCandidate.valid(0, 176.7, 0.25)
        (1..7).forEach { second ->
            withCandidate.valid(
                timestampMs = second * 1_000L,
                knee = 176.0,
                hipY = 0.25,
                side = PoseSide.RIGHT,
            )
        }
        val provisional =
            withCandidate.valid(8_100, 176.0, 0.25, side = PoseSide.RIGHT)

        assertEquals(SquatState.STANDING, withCandidate.state)
        assertEquals(
            "CALIBRATION_TIMEOUT_USED_PROVISIONAL",
            provisional.diagnostics.lastResetReason,
        )
        assertTrue(provisional.diagnostics.candidateBufferPreserved)

        val empty = SquatStateMachine(config)
        empty.valid(0, 140.0, 0.25)
        (1..7).forEach { second -> empty.valid(second * 1_000L, 140.0, 0.25) }
        val reset = empty.valid(8_100, 140.0, 0.25)
        assertEquals(SquatState.CALIBRATING, empty.state)
        assertEquals("CALIBRATION_TIMEOUT_NO_CANDIDATE", reset.diagnostics.lastResetReason)
        assertEquals(0, reset.diagnostics.calibrationSampleCount)
    }

    @Test
    fun irregularRealCameraLogCalibratesAndProducesExactlyOneKneeOnlyRep() {
        val detector = SquatStateMachine(config)
        val frames =
            listOf(
                CameraLogFrame(0, 178.7),
                CameraLogFrame(500, rejectReason = "lowerBodyConfidenceLow"),
                CameraLogFrame(1_000, 144.7),
                CameraLogFrame(1_600, 137.1),
                CameraLogFrame(2_200, rejectReason = "lowerBodyTooSmall"),
                CameraLogFrame(2_800, 129.7),
                CameraLogFrame(3_400, 132.0),
                CameraLogFrame(4_000, 138.5),
                CameraLogFrame(4_600, 150.8),
                CameraLogFrame(5_200, 136.8),
                CameraLogFrame(7_501, 171.1),
                CameraLogFrame(8_001, 176.7),
                CameraLogFrame(8_501, 175.4),
                CameraLogFrame(9_001, 176.7),
                CameraLogFrame(9_501, 171.0),
                CameraLogFrame(10_001, 174.2),
                CameraLogFrame(10_501, 167.3),
                CameraLogFrame(11_001, 175.7),
                CameraLogFrame(11_501, 169.3),
                CameraLogFrame(12_001, 179.8),
                CameraLogFrame(12_501, 172.3),
                CameraLogFrame(13_001, 176.9),
                CameraLogFrame(13_501, 172.1),
                CameraLogFrame(14_001, 179.9),
                CameraLogFrame(14_501, 140.5),
                CameraLogFrame(15_001, 115.9),
                CameraLogFrame(15_501, 133.8),
                CameraLogFrame(16_001, 109.0),
                CameraLogFrame(16_501, 105.1),
                CameraLogFrame(17_001, 95.7),
                CameraLogFrame(17_501, 86.9),
                CameraLogFrame(18_001, 134.1),
                CameraLogFrame(18_501, 144.3),
                CameraLogFrame(19_001, 156.6),
                CameraLogFrame(19_501, 164.1),
                CameraLogFrame(20_001, 178.6),
                CameraLogFrame(20_501, 174.9),
                CameraLogFrame(21_001, 173.9),
                CameraLogFrame(21_501, 170.4),
            )
        val updates =
            frames.map { frame ->
                frame.knee?.let { detector.valid(frame.timestampMs, it, 0.25) }
                    ?: detector.invalid(frame.timestampMs, requireNotNull(frame.rejectReason))
            }
        val accepted = updates.single { it.repCompleted }

        assertEquals(1, detector.repSequence)
        assertEquals(1, updates.count { it.repCompleted })
        assertTrue(accepted.diagnostics.calibratedStandingKneeAngleDeg!! in 170.0..180.0)
        assertEquals(86.9, accepted.diagnostics.minimumAttemptKneeAngleDeg!!, 0.001)
        assertTrue(accepted.diagnostics.kneeBendDeltaDeg!! >= 80.0)
        assertEquals(BottomEvidencePath.KNEE_ONLY, accepted.diagnostics.bottomEvidencePath)
        assertEquals("REP_ACCEPTED", accepted.diagnostics.lastTransitionReason)
    }

    @Test
    fun normalSquatProducesExactlyOneRepAfterReturnToStanding() {
        val detector = calibratedDetector()
        val updates = normalRep(detector, CALIBRATED_AT + 200)

        assertEquals(1, updates.count { it.repCompleted })
        assertEquals(1, detector.repSequence)
        assertEquals(SquatState.STANDING, detector.state)
        assertEquals("REP_ACCEPTED", updates.last().diagnostics.lastTransitionReason)
    }

    @Test
    fun irregularFiveFpsNormalSquatProducesExactlyOneRep() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        val updates =
            listOf(
                detector.valid(start, 150.0, 0.285),
                detector.valid(start + 220, 145.0, 0.290),
                detector.valid(start + 430, 133.0, 0.305),
                detector.valid(start + 650, 132.0, 0.305),
                detector.valid(start + 880, 140.0, 0.290),
                detector.valid(start + 1_100, 150.0, 0.280),
                detector.valid(start + 1_330, 154.0, 0.270),
                detector.valid(start + 1_560, 160.0, 0.260),
            )

        assertEquals(1, updates.count { it.repCompleted })
    }

    @Test
    fun irregularTwoFpsNormalSquatProducesExactlyOneRep() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        val updates =
            listOf(
                detector.valid(start, 150.0, 0.26),
                detector.valid(start + 500, 143.0, 0.27),
                detector.valid(start + 1_000, 132.0, 0.30),
                detector.valid(start + 1_500, 145.0, 0.27),
            )

        assertEquals(1, updates.count { it.repCompleted })
    }

    @Test
    fun irregularFourFpsNormalSquatProducesExactlyOneRep() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        val updates =
            listOf(
                detector.valid(start, 150.0, 0.26),
                detector.valid(start + 250, 145.0, 0.27),
                detector.valid(start + 500, 138.0, 0.29),
                detector.valid(start + 750, 132.0, 0.30),
                detector.valid(start + 1_000, 138.0, 0.29),
                detector.valid(start + 1_250, 145.0, 0.27),
            )

        assertEquals(1, updates.count { it.repCompleted })
    }

    @Test
    fun irregularEightFpsNormalSquatProducesExactlyOneRep() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        val updates = mutableListOf<SquatDetectorUpdate>()
        listOf(
            Triple(0L, 150.0, 0.285),
            Triple(130L, 146.0, 0.290),
            Triple(270L, 138.0, 0.295),
            Triple(410L, 133.0, 0.305),
            Triple(570L, 132.0, 0.305),
            Triple(710L, 138.0, 0.295),
            Triple(850L, 145.0, 0.290),
            Triple(1_020L, 151.0, 0.280),
            Triple(1_240L, 154.0, 0.270),
            Triple(1_470L, 160.0, 0.260),
        ).forEach { (offset, knee, hip) -> updates += detector.valid(start + offset, knee, hip) }

        assertEquals(1, updates.count { it.repCompleted })
    }

    @Test
    fun standingCanSkipDescendingAndObserveBottomDirectly() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200

        detector.valid(start, 132.0, 0.305)
        val bottom = detector.valid(start + 150, 131.0, 0.305)

        assertEquals(SquatState.BOTTOM, detector.state)
        assertTrue(bottom.diagnostics.bottomReached)
        assertEquals("BOTTOM_BY_KNEE", bottom.diagnostics.lastTransitionReason)
        assertEquals(1, directReturnToStanding(detector, start + 800).count { it.repCompleted })
    }

    @Test
    fun bottomCanSkipAscendingAndReturnDirectlyToStanding() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        descendToBottom(detector, start)

        val updates = directReturnToStanding(detector, start + 1_000)

        assertEquals(1, updates.count { it.repCompleted })
        assertEquals(1, detector.repSequence)
    }

    @Test
    fun tenNormalSquatsProduceExactlyTenMonotonicReps() {
        val detector = calibratedDetector()
        val sequences = mutableListOf<Int>()
        var start = CALIBRATED_AT + 200
        repeat(10) {
            sequences += normalRep(detector, start)
                .filter { it.repCompleted }
                .map { it.repSequence }
            start += 2_200
        }

        assertEquals((1..10).toList(), sequences)
        assertEquals(10, detector.repSequence)
    }

    @Test
    fun tenShallowSquatsNeverCount() {
        val detector = calibratedDetector()
        var start = CALIBRATED_AT + 200
        repeat(10) {
            shallowRep(detector, start)
            start += 1_400
        }

        assertEquals(0, detector.repSequence)
    }

    @Test
    fun standingJitterAndTenDegreeKneeBendNeverCount() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        listOf(168.0, 166.0, 170.0, 158.0, 160.0, 166.0, 168.0).forEachIndexed {
                index,
                knee,
            ->
            detector.valid(start + index * 250L, knee, 0.25)
        }

        assertEquals(0, detector.repSequence)
    }

    @Test
    fun deepSquatIsAcceptedInsteadOfRejected() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        val updates = mutableListOf<SquatDetectorUpdate>()
        updates += detector.valid(start, 146.0, 0.285)
        updates += detector.valid(start + 150, 140.0, 0.290)
        updates += detector.valid(start + 350, 105.0, 0.285)
        updates += detector.valid(start + 500, 100.0, 0.285)
        updates += detector.valid(start + 750, 140.0, 0.290)
        updates += detector.valid(start + 950, 151.0, 0.280)
        updates += detector.valid(start + 1_150, 154.0, 0.270)
        updates += detector.valid(start + 1_400, 160.0, 0.260)

        assertEquals(1, updates.count { it.repCompleted })
        assertEquals(1, detector.repSequence)
    }

    @Test
    fun forwardBendHipDropWithoutKneeFlexionNeverCounts() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        listOf(
            detector.valid(start, 168.0, 0.285),
            detector.valid(start + 200, 166.0, 0.310),
            detector.valid(start + 450, 168.0, 0.315),
            detector.valid(start + 700, 165.0, 0.270),
            detector.valid(start + 1_000, 165.0, 0.260),
        )

        assertEquals(0, detector.repSequence)
    }

    @Test
    fun incompleteDescentDoesNotCount() {
        val detector = calibratedDetector()

        shallowRep(detector, CALIBRATED_AT + 200)

        assertEquals(0, detector.repSequence)
    }

    @Test
    fun missingReturnToStandingDoesNotCount() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        descendToBottom(detector, start)
        detector.valid(start + 800, 125.0, 0.300)
        detector.valid(start + 1_000, 128.0, 0.295)
        detector.valid(start + 1_300, 130.0, 0.290)

        assertEquals(0, detector.repSequence)
    }

    @Test
    fun bottomBounceCannotCreateDuplicateRep() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        val updates = descendToBottom(detector, start).toMutableList()
        updates += detector.valid(start + 800, 140.0, 0.290)
        updates += detector.valid(start + 950, 146.0, 0.285)
        updates += detector.valid(start + 1_100, 132.0, 0.305)
        updates += detector.valid(start + 1_300, 130.0, 0.310)
        updates += detector.valid(start + 1_500, 142.0, 0.290)
        updates += detector.valid(start + 1_650, 150.0, 0.280)
        updates += detector.valid(start + 1_850, 154.0, 0.270)
        updates += detector.valid(start + 2_100, 160.0, 0.260)
        updates += detector.valid(start + 2_200, 160.0, 0.260)

        assertEquals(1, updates.count { it.repCompleted })
        assertEquals(1, detector.repSequence)
    }

    @Test
    fun sevenHundredMillisecondFrameGapKeepsPhaseAndBottomReached() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        descendToBottom(detector, start)
        assertEquals(SquatState.BOTTOM, detector.state)

        val afterGap = detector.valid(start + 1_250, 135.0, 0.300)

        assertEquals(SquatState.BOTTOM, detector.state)
        assertTrue(afterGap.diagnostics.bottomReached)
        assertNull(afterGap.diagnostics.kneeAngularVelocity)
        assertEquals(700L, afterGap.diagnostics.frameDtMs)
        assertFalse(afterGap.diagnostics.lastResetReason == "RESET_FRAME_GAP")
    }

    @Test
    fun thirtyNineHundredMillisecondPoseLossDoesNotResetOnEmulator() {
        val detector = calibratedDetector(isEmulator = true)
        val start = CALIBRATED_AT + 200
        descendToBottom(detector, start)

        val update = detector.invalid(start + 4_450)

        assertEquals(SquatState.BOTTOM, detector.state)
        assertTrue(update.diagnostics.bottomReached)
    }

    @Test
    fun poseLossLongerThanFourThousandMillisecondsResetsEmulatorAttempt() {
        val detector = calibratedDetector(isEmulator = true)
        val start = CALIBRATED_AT + 200
        descendToBottom(detector, start)

        val reset = detector.invalid(start + 4_551)

        assertEquals(SquatState.CALIBRATING, detector.state)
        assertFalse(reset.diagnostics.bottomReached)
        assertEquals("RESET_POSE_LOSS_TIMEOUT", reset.diagnostics.lastResetReason)
    }

    @Test
    fun physicalPoseLossLongerThanTwoThousandMillisecondsResetsAttempt() {
        val detector = calibratedDetector()
        val start = CALIBRATED_AT + 200
        descendToBottom(detector, start)

        val reset = detector.invalid(start + 2_551)

        assertEquals(SquatState.CALIBRATING, detector.state)
        assertFalse(reset.diagnostics.bottomReached)
        assertEquals("RESET_POSE_LOSS_TIMEOUT", reset.diagnostics.lastResetReason)
    }

    @Test
    fun returnAfterPoseLossTimeoutCannotAcceptDiscardedAttempt() {
        val detector = SquatStateMachine(config)
        detector.valid(0, 176.7, 0.25)
        detector.valid(500, 140.5, 0.30)
        detector.invalid(2_501)
        val returned = detector.valid(3_000, 170.0, 0.25)

        assertEquals(SquatState.CALIBRATING, detector.state)
        assertFalse(returned.repCompleted)
        assertEquals(0, detector.repSequence)
    }

    @Test
    fun twentyFiveHundredMillisecondValidGapPreservesEmulatorAttemptExtrema() {
        val detector = calibratedDetector(isEmulator = true)
        val start = CALIBRATED_AT + 200
        descendToBottom(detector, start)

        val afterGap = detector.valid(start + 3_050, 135.0, 0.30)

        assertEquals(SquatState.BOTTOM, detector.state)
        assertTrue(afterGap.diagnostics.bottomReached)
        assertEquals(132.0, afterGap.diagnostics.minimumAttemptKneeAngleDeg!!, 0.001)
        assertEquals(0.11, afterGap.diagnostics.maximumAttemptHipDropRatio!!, 0.001)
        assertNull(afterGap.diagnostics.kneeAngularVelocity)
    }

    @Test
    fun duplicateAndOutOfOrderTimestampsAreRejected() {
        val detector = calibratedDetector()
        val time = CALIBRATED_AT + 200
        detector.valid(time, 146.0, 0.285)

        val duplicate = detector.valid(time, 100.0, 0.320)
        val reversed = detector.valid(time - 1, 100.0, 0.320)

        assertEquals("REJECT_DUPLICATE_TIMESTAMP", duplicate.diagnostics.latestRejectReason)
        assertEquals("REJECT_DUPLICATE_TIMESTAMP", reversed.diagnostics.latestRejectReason)
        assertEquals(0, detector.repSequence)
    }

    @Test
    fun minimumAndMaximumRepDurationAreEnforced() {
        val fast = calibratedDetector()
        val fastStart = CALIBRATED_AT + 200
        fast.valid(fastStart, 132.0, 0.305)
        fast.valid(fastStart + 125, 131.0, 0.305)
        val fastRejected = fast.valid(fastStart + 350, 154.0, 0.270)
        fast.valid(fastStart + 560, 160.0, 0.260)
        assertEquals(0, fast.repSequence)
        assertEquals("REJECT_DURATION", fastRejected.diagnostics.latestRejectReason)

        val slow = calibratedDetector(isEmulator = true)
        val slowStart = CALIBRATED_AT + 200
        descendToBottom(slow, slowStart)
        slow.valid(slowStart + 3_500, 125.0, 0.300)
        slow.valid(slowStart + 7_000, 125.0, 0.300)
        slow.valid(slowStart + 10_500, 125.0, 0.300)
        val slowRejected = slow.valid(slowStart + 12_400, 125.0, 0.300)
        assertEquals(SquatState.CALIBRATING, slow.state)
        assertEquals("RESET_REP_TIMEOUT", slowRejected.diagnostics.lastResetReason)
    }

    private fun calibratedDetector(isEmulator: Boolean = false): SquatStateMachine {
        val detector = SquatStateMachine(config, isEmulator)
        CALIBRATION_TIMES.forEach { time -> detector.valid(time, 168.0, 0.25) }
        assertEquals(SquatState.STANDING, detector.state)
        return detector
    }

    private fun normalRep(
        detector: SquatStateMachine,
        start: Long,
    ): List<SquatDetectorUpdate> {
        val updates = mutableListOf<SquatDetectorUpdate>()
        updates += detector.valid(start, 150.0, 0.260)
        updates += detector.valid(start + 250, 143.0, 0.270)
        updates += detector.valid(start + 600, 132.0, 0.300)
        updates += detector.valid(start + 1_000, 145.0, 0.270)
        return updates
    }

    private fun descendToBottom(
        detector: SquatStateMachine,
        start: Long,
    ) = listOf(
        detector.valid(start, 150.0, 0.285),
        detector.valid(start + 150, 145.0, 0.290),
        detector.valid(start + 350, 133.0, 0.305),
        detector.valid(start + 550, 132.0, 0.305),
    )

    private fun directReturnToStanding(
        detector: SquatStateMachine,
        start: Long,
    ) = listOf(
        detector.valid(start, 154.0, 0.270),
        detector.valid(start + 220, 160.0, 0.260),
    )

    private fun shallowRep(
        detector: SquatStateMachine,
        start: Long,
    ) {
        detector.valid(start, 164.0, 0.260)
        detector.valid(start + 200, 162.0, 0.265)
        detector.valid(start + 450, 160.5, 0.268)
        detector.valid(start + 900, 164.0, 0.260)
        detector.valid(start + 1_100, 165.0, 0.260)
    }

    private fun SquatStateMachine.valid(
        timestampMs: Long,
        knee: Double,
        hipY: Double,
        side: PoseSide = PoseSide.LEFT,
    ) = process(
        PoseFeatureResult.Valid(
            sample =
                PoseFeatureSample(
                    timestampMs = timestampMs,
                    kneeAngleDeg = knee,
                    rawKneeAngleDeg = knee,
                    hipY = hipY,
                    legLength = 0.50,
                    confidence = 0.90,
                    selectedSide = side,
                ),
            quality =
                PoseQualityMetrics.EMPTY.copy(
                    poseDetected = true,
                    selectedSide = side,
                    trackingStatus = PoseTrackingStatus.VALID,
                ),
        ),
    )

    private fun SquatStateMachine.invalid(
        timestampMs: Long,
        reason: String = "poseNotDetected",
    ) =
        process(
            PoseFeatureResult.Invalid(
                timestampMs = timestampMs,
                warning =
                    when (reason) {
                        "lowerBodyConfidenceLow" -> PoseQualityWarning.LOW_LIGHT_OR_CONFIDENCE
                        "lowerBodyTooSmall" -> PoseQualityWarning.MOVE_CLOSER
                        else -> PoseQualityWarning.NO_POSE_DETECTED
                    },
                quality = PoseQualityMetrics.EMPTY.copy(trackingStatus = PoseTrackingStatus.NO_POSE),
                rejectReason = reason,
            ),
        )

    private fun SquatStateMachine.calibrationCandidate(
        timestampMs: Long,
        knee: Double,
        path: CalibrationQualityPath,
    ) = process(calibrationCandidateResult(timestampMs, knee, path))

    private fun calibrationCandidateResult(
        timestampMs: Long,
        knee: Double,
        path: CalibrationQualityPath,
    ) = PoseFeatureResult.CalibrationCandidate(
        sample =
            PoseFeatureSample(
                timestampMs = timestampMs,
                kneeAngleDeg = knee,
                hipY = 0.25,
                legLength = 0.50,
                confidence = 0.40,
                selectedSide = PoseSide.LEFT,
            ),
        qualityPath = path,
        warning = PoseQualityWarning.LOW_LIGHT_OR_CONFIDENCE,
        rejectReason = "lowerBodyConfidenceLow",
        quality =
            PoseQualityMetrics.EMPTY.copy(
                poseDetected = true,
                selectedSide = PoseSide.LEFT,
                trackingStatus = PoseTrackingStatus.CONFIDENCE_INSUFFICIENT,
            ),
    )

    private data class CameraLogFrame(
        val timestampMs: Long,
        val knee: Double? = null,
        val rejectReason: String? = null,
    )

    private companion object {
        val CALIBRATION_TIMES = listOf(0L, 300L, 600L, 900L, 1_200L, 1_500L, 1_800L, 2_100L)
        const val CALIBRATED_AT = 2_100L
    }
}
