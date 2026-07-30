package com.kren.michizure.pose

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.drawable.ColorDrawable
import android.view.View
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import androidx.camera.view.PreviewView
import androidx.camera.view.transform.CoordinateTransform
import androidx.camera.view.transform.OutputTransform
import kotlin.math.max

internal data class SquatGuideFrame(
    val sourceTransform: OutputTransform,
    val hip: PosePoint?,
    val knee: PosePoint?,
    val trackingStatus: PoseTrackingStatus,
    val state: SquatState,
    val timestampMs: Long,
)

internal data class SquatGuideDrawing(
    val hipX: Float?,
    val hipY: Float?,
    val kneeX: Float?,
    val kneeY: Float?,
    val trackingStatus: PoseTrackingStatus,
    val state: SquatState,
)

/**
 * One native coordinate space for the PreviewView and its guide overlay.
 *
 * PreviewView must use COMPATIBLE mode because CameraX documents that
 * getOutputTransform() may not respect the View matrix in PERFORMANCE mode.
 */
class SquatCameraContainer(
    context: Context,
    private val config: SquatDetectorConfig = SquatDetectorConfig(),
) : FrameLayout(context) {
    val previewView =
        PreviewView(context).apply {
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            scaleType = PreviewView.ScaleType.FIT_CENTER
            background = ColorDrawable(Color.BLACK)
        }
    internal val guideOverlayView = SquatGuideOverlayView(context, config)
    private var lastGuideTimestampMs = Long.MIN_VALUE

    init {
        background = ColorDrawable(Color.BLACK)
        clipChildren = true
        clipToPadding = true
        val radius = CORNER_RADIUS_DP * resources.displayMetrics.density
        outlineProvider =
            object : ViewOutlineProvider() {
                override fun getOutline(
                    view: View,
                    outline: android.graphics.Outline,
                ) {
                    outline.setRoundRect(0, 0, view.width, view.height, radius)
                }
            }
        clipToOutline = true
        addView(previewView, matchParentLayoutParams())
        addView(guideOverlayView, matchParentLayoutParams())
    }

    internal fun updateGuide(frame: SquatGuideFrame) {
        if (frame.timestampMs <= lastGuideTimestampMs) return
        val minimumIntervalMs = 1_000L / config.nativeOverlayFps
        if (lastGuideTimestampMs != Long.MIN_VALUE &&
            frame.timestampMs - lastGuideTimestampMs < minimumIntervalMs
        ) {
            return
        }
        lastGuideTimestampMs = frame.timestampMs
        post {
            val targetTransform = previewView.outputTransform ?: return@post
            val coordinates =
                floatArrayOf(
                    frame.hip?.x?.toFloat() ?: Float.NaN,
                    frame.hip?.y?.toFloat() ?: Float.NaN,
                    frame.knee?.x?.toFloat() ?: Float.NaN,
                    frame.knee?.y?.toFloat() ?: Float.NaN,
                )
            val validIndices =
                buildList {
                    if (coordinates[0].isFinite() && coordinates[1].isFinite()) add(0)
                    if (coordinates[2].isFinite() && coordinates[3].isFinite()) add(2)
                }
            if (validIndices.isNotEmpty()) {
                val compact =
                    validIndices.flatMap { index ->
                        listOf(coordinates[index], coordinates[index + 1])
                    }.toFloatArray()
                CoordinateTransform(frame.sourceTransform, targetTransform).mapPoints(compact)
                validIndices.forEachIndexed { compactIndex, destinationIndex ->
                    coordinates[destinationIndex] = compact[compactIndex * 2]
                    coordinates[destinationIndex + 1] = compact[compactIndex * 2 + 1]
                }
            }
            guideOverlayView.update(
                SquatGuideDrawing(
                    hipX = coordinates[0].takeIf(Float::isFinite),
                    hipY = coordinates[1].takeIf(Float::isFinite),
                    kneeX = coordinates[2].takeIf(Float::isFinite),
                    kneeY = coordinates[3].takeIf(Float::isFinite),
                    trackingStatus = frame.trackingStatus,
                    state = frame.state,
                ),
            )
        }
    }

    internal fun clearGuide() {
        lastGuideTimestampMs = Long.MIN_VALUE
        post { guideOverlayView.update(null) }
    }

    private fun matchParentLayoutParams() =
        LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)

    private companion object {
        const val CORNER_RADIUS_DP = 20f
    }
}

internal class SquatGuideOverlayView(
    context: Context,
    private val config: SquatDetectorConfig = SquatDetectorConfig(),
) : View(context) {
    private val density = resources.displayMetrics.density
    private val guidePaint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 2f * density
            color = Color.argb(210, 255, 255, 255)
        }
    private val bandFillPaint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
        }
    private val bandStrokePaint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 2f * density
        }
    private val textPaint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = 14f * density
            color = Color.WHITE
            setShadowLayer(3f * density, 0f, density, Color.BLACK)
        }
    private var drawing: SquatGuideDrawing? = null

    fun update(value: SquatGuideDrawing?) {
        drawing = value
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val horizontalInset = width * GUIDE_HORIZONTAL_INSET_RATIO
        val verticalInset = height * GUIDE_VERTICAL_INSET_RATIO
        val guide =
            RectF(
                horizontalInset,
                verticalInset,
                width - horizontalInset,
                height - verticalInset,
            )
        canvas.drawRoundRect(guide, 24f * density, 24f * density, guidePaint)

        val current = drawing
        val color =
            when {
                current == null ||
                    current.trackingStatus != PoseTrackingStatus.VALID -> Color.rgb(244, 67, 54)
                current.state == SquatState.BOTTOM -> Color.rgb(255, 167, 38)
                current.state == SquatState.STANDING -> Color.rgb(102, 187, 106)
                else -> Color.rgb(41, 182, 246)
            }
        bandFillPaint.color = Color.argb(58, Color.red(color), Color.green(color), Color.blue(color))
        bandStrokePaint.color = color
        current?.hipY?.let { drawBand(canvas, "HIP", it, color) }
        current?.kneeY?.let { drawBand(canvas, "KNEE", it, color) }

        val statusText =
            when (current?.trackingStatus) {
                PoseTrackingStatus.NO_POSE, null -> "POSE: NOT DETECTED"
                PoseTrackingStatus.HIP_UNAVAILABLE -> "POSE: HIP MISSING"
                PoseTrackingStatus.KNEE_UNAVAILABLE -> "POSE: KNEE MISSING"
                PoseTrackingStatus.CONFIDENCE_INSUFFICIENT -> "POSE: LOW CONFIDENCE"
                PoseTrackingStatus.VALID -> "POSE: ${current.state.wireValue.uppercase()}"
            }
        textPaint.color = color
        canvas.drawText(statusText, horizontalInset, max(textPaint.textSize, verticalInset - 8f), textPaint)
    }

    private fun drawBand(
        canvas: Canvas,
        label: String,
        centerY: Float,
        color: Int,
    ) {
        val tolerance = height * config.overlayBandToleranceRatio.toFloat()
        val rect =
            RectF(
                width * GUIDE_HORIZONTAL_INSET_RATIO,
                centerY - tolerance,
                width * (1f - GUIDE_HORIZONTAL_INSET_RATIO),
                centerY + tolerance,
            )
        canvas.drawRoundRect(rect, tolerance / 2, tolerance / 2, bandFillPaint)
        canvas.drawRoundRect(rect, tolerance / 2, tolerance / 2, bandStrokePaint)
        textPaint.color = color
        canvas.drawText(label, rect.left + 8f * density, centerY + textPaint.textSize / 3, textPaint)
    }

    private companion object {
        const val GUIDE_HORIZONTAL_INSET_RATIO = 0.10f
        const val GUIDE_VERTICAL_INSET_RATIO = 0.08f
    }
}
