package com.kren.michizure.pose

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.graphics.drawable.ColorDrawable
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.camera.view.PreviewView
import androidx.camera.view.transform.CoordinateTransform
import androidx.camera.view.transform.OutputTransform
import kotlin.math.max

data class SquatGuideFrame(
    val timestampMs: Long,
    val sourceTransform: OutputTransform,
    val hip: PosePoint?,
    val knee: PosePoint?,
    val ankle: PosePoint?,
    val trackingStatus: PoseTrackingStatus,
    val state: SquatState,
)

internal data class SquatGuideDrawing(
    val hip: PointF?,
    val knee: PointF?,
    val ankle: PointF?,
    val trackingStatus: PoseTrackingStatus,
    val state: SquatState,
)

/**
 * Owns the camera preview and guide in one native coordinate system.
 *
 * COMPATIBLE mode is required because PreviewView.getOutputTransform() does
 * not include every View transform when PERFORMANCE mode uses SurfaceView.
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
    internal val guideOverlayView = SquatGuideOverlayView(context)
    private var lastGuideTimestampMs = Long.MIN_VALUE

    init {
        background = ColorDrawable(Color.BLACK)
        clipChildren = true
        clipToPadding = true
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
            val sourcePoints = listOf(frame.hip, frame.knee, frame.ankle)
            val compact = mutableListOf<Float>()
            val indexes = mutableListOf<Int>()
            sourcePoints.forEachIndexed { index, point ->
                if (point != null && point.x.isFinite() && point.y.isFinite()) {
                    indexes += index
                    compact += point.x.toFloat()
                    compact += point.y.toFloat()
                }
            }
            val mapped = arrayOfNulls<PointF>(sourcePoints.size)
            if (compact.isNotEmpty()) {
                val values = compact.toFloatArray()
                CoordinateTransform(frame.sourceTransform, targetTransform).mapPoints(values)
                indexes.forEachIndexed { compactIndex, destinationIndex ->
                    mapped[destinationIndex] =
                        PointF(values[compactIndex * 2], values[compactIndex * 2 + 1])
                }
            }
            guideOverlayView.update(
                SquatGuideDrawing(
                    hip = mapped[0],
                    knee = mapped[1],
                    ankle = mapped[2],
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
        LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
}

internal class SquatGuideOverlayView(context: Context) : View(context) {
    private val guidePaint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(210, 255, 255, 255)
            style = Paint.Style.STROKE
            strokeWidth = dp(2f)
        }
    private val detectedPaint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(88, 214, 141)
            style = Paint.Style.STROKE
            strokeWidth = dp(4f)
        }
    private val missingPaint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(255, 183, 77)
            style = Paint.Style.STROKE
            strokeWidth = dp(3f)
        }
    private val textPaint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = dp(14f)
            setShadowLayer(dp(3f), 0f, dp(1f), Color.BLACK)
        }
    private var drawing: SquatGuideDrawing? = null

    fun update(next: SquatGuideDrawing?) {
        drawing = next
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val inset = dp(18f)
        val top = height * 0.08f
        val bottom = height * 0.94f
        val path =
            Path().apply {
                moveTo(inset + dp(26f), top)
                lineTo(inset, top)
                lineTo(inset, top + dp(26f))
                moveTo(width - inset - dp(26f), top)
                lineTo(width - inset, top)
                lineTo(width - inset, top + dp(26f))
                moveTo(inset, bottom - dp(26f))
                lineTo(inset, bottom)
                lineTo(inset + dp(26f), bottom)
                moveTo(width - inset - dp(26f), bottom)
                lineTo(width - inset, bottom)
                lineTo(width - inset, bottom - dp(26f))
            }
        canvas.drawPath(path, guidePaint)

        val current = drawing
        if (current == null) {
            canvas.drawText("胸の下から足首まで映してください", inset, top + dp(30f), textPaint)
            return
        }
        val pointPaint =
            if (current.trackingStatus == PoseTrackingStatus.VALID) {
                detectedPaint
            } else {
                missingPaint
            }
        listOfNotNull(current.hip, current.knee, current.ankle).forEach { point ->
            canvas.drawCircle(point.x, point.y, dp(7f), pointPaint)
        }
        current.hip?.let { hip ->
            current.knee?.let { knee -> canvas.drawLine(hip.x, hip.y, knee.x, knee.y, pointPaint) }
        }
        current.knee?.let { knee ->
            current.ankle?.let { ankle ->
                canvas.drawLine(knee.x, knee.y, ankle.x, ankle.y, pointPaint)
            }
        }
        canvas.drawText(
            "${current.trackingStatus.displayLabel} / ${current.state.wireValue}",
            inset,
            max(top + dp(30f), dp(24f)),
            textPaint,
        )
    }

    private fun dp(value: Float): Float = value * resources.displayMetrics.density
}

private val PoseTrackingStatus.displayLabel: String
    get() =
        when (this) {
            PoseTrackingStatus.NO_POSE -> "人物なし"
            PoseTrackingStatus.HIP_UNAVAILABLE -> "腰なし"
            PoseTrackingStatus.KNEE_UNAVAILABLE -> "膝なし"
            PoseTrackingStatus.ANKLE_UNAVAILABLE -> "足首なし"
            PoseTrackingStatus.CONFIDENCE_INSUFFICIENT -> "信頼度不足"
            PoseTrackingStatus.VALID -> "検出"
        }
