package com.kren.michizure.pose

import android.content.Context
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.graphics.RectF
import android.graphics.drawable.ColorDrawable
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
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
    val pipelineStatus: PosePipelineStatus,
    val state: SquatState,
)

data class HostSquatGuideFrame(
    val frameId: Long,
    val bitmap: Bitmap,
    val imageWidth: Int,
    val imageHeight: Int,
    val hip: PosePoint?,
    val knee: PosePoint?,
    val ankle: PosePoint?,
    val pipelineStatus: PosePipelineStatus,
    val state: SquatState,
)

internal data class SquatGuideDrawing(
    val hip: PointF?,
    val knee: PointF?,
    val ankle: PointF?,
    val pipelineStatus: PosePipelineStatus,
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
    initialHostPoseMode: Boolean = false,
    private val config: SquatDetectorConfig = SquatDetectorConfig(),
) : FrameLayout(context) {
    val previewView: PreviewView by lazy {
        PreviewView(context).apply {
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            scaleType = PreviewView.ScaleType.FIT_CENTER
            background = ColorDrawable(Color.BLACK)
        }
    }
    private val hostImageView =
        ImageView(context).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            background = ColorDrawable(Color.BLACK)
        }
    internal val guideOverlayView = SquatGuideOverlayView(context)
    private var lastGuideTimestampMs = Long.MIN_VALUE
    private var hostPoseMode = initialHostPoseMode
    private var pendingHostFrame: HostSquatGuideFrame? = null
    private var hostRenderPosted = false
    private var displayedHostBitmap: Bitmap? = null
    private var debugThumbnailEnabled = false

    init {
        background = ColorDrawable(Color.BLACK)
        clipChildren = true
        clipToPadding = true
        addView(backgroundView(), matchParentLayoutParams())
        addView(guideOverlayView, matchParentLayoutParams())
        guideOverlayView.setHostPoseMode(hostPoseMode)
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
                    pipelineStatus = frame.pipelineStatus,
                    state = frame.state,
                ),
            )
        }
    }

    internal fun updatePipelineStatus(snapshot: PosePipelineStatusSnapshot) {
        post {
            guideOverlayView.updateStatus(snapshot.status)
        }
    }

    internal fun setHostPoseMode(enabled: Boolean) {
        if (hostPoseMode == enabled) return
        hostPoseMode = enabled
        post {
            removeView(if (enabled) previewView else hostImageView)
            addView(backgroundView(), 0, matchParentLayoutParams())
            guideOverlayView.setHostPoseMode(enabled)
        }
    }

    internal fun updateHostFrame(
        frame: HostSquatGuideFrame,
        onDisplayed: () -> Unit,
        onDropped: () -> Unit,
    ) {
        synchronized(this) {
            pendingHostFrame?.bitmap?.takeIf { !it.isRecycled }?.recycle()
            if (pendingHostFrame != null) onDropped()
            pendingHostFrame = frame
            if (hostRenderPosted) return
            hostRenderPosted = true
        }
        post {
            val latest =
                synchronized(this) {
                    hostRenderPosted = false
                    pendingHostFrame.also { pendingHostFrame = null }
                } ?: return@post
            if (!hostPoseMode) {
                latest.bitmap.recycle()
                onDropped()
                return@post
            }
            val mapped =
                mapHostPoints(
                    latest.imageWidth,
                    latest.imageHeight,
                    listOf(latest.hip, latest.knee, latest.ankle),
                )
            val previous = displayedHostBitmap
            displayedHostBitmap = latest.bitmap
            hostImageView.setImageBitmap(latest.bitmap)
            guideOverlayView.update(
                SquatGuideDrawing(
                    hip = mapped[0],
                    knee = mapped[1],
                    ankle = mapped[2],
                    pipelineStatus = latest.pipelineStatus,
                    state = latest.state,
                ),
            )
            previous?.takeIf { it !== latest.bitmap && !it.isRecycled }?.recycle()
            onDisplayed()
        }
    }

    internal fun updateHostMetrics(videoFps: Double, poseFps: Double) {
        post { guideOverlayView.updateHostMetrics(videoFps, poseFps) }
    }

    internal fun updateDebugThumbnail(bitmap: Bitmap) {
        if (!isDebuggable || !debugThumbnailEnabled) return
        val nowMs = SystemClock.elapsedRealtime()
        if (nowMs - lastDebugThumbnailMs < DEBUG_THUMBNAIL_INTERVAL_MS) return
        lastDebugThumbnailMs = nowMs
        val thumbnail =
            Bitmap.createScaledBitmap(
                bitmap,
                DEBUG_THUMBNAIL_WIDTH,
                (bitmap.height * DEBUG_THUMBNAIL_WIDTH / bitmap.width).coerceAtLeast(1),
                true,
            )
        post { guideOverlayView.updateDebugThumbnail(thumbnail) }
    }

    internal fun setDebugThumbnailEnabled(enabled: Boolean) {
        if (!isDebuggable) return
        debugThumbnailEnabled = enabled
        if (!enabled) post { guideOverlayView.clearDebugThumbnail() }
    }

    internal fun clearGuide() {
        lastGuideTimestampMs = Long.MIN_VALUE
        synchronized(this) {
            pendingHostFrame?.bitmap?.takeIf { !it.isRecycled }?.recycle()
            pendingHostFrame = null
        }
        post {
            hostImageView.setImageDrawable(ColorDrawable(Color.BLACK))
            displayedHostBitmap?.takeIf { !it.isRecycled }?.recycle()
            displayedHostBitmap = null
            guideOverlayView.clear()
            guideOverlayView.setHostPoseMode(hostPoseMode)
        }
    }

    private fun backgroundView(): View = if (hostPoseMode) hostImageView else previewView

    private fun mapHostPoints(
        imageWidth: Int,
        imageHeight: Int,
        points: List<PosePoint?>,
    ): List<PointF?> {
        if (width <= 0 || height <= 0) return List(points.size) { null }
        val scale = max(width.toFloat() / imageWidth, height.toFloat() / imageHeight)
        val offsetX = (width - imageWidth * scale) / 2f
        val offsetY = (height - imageHeight * scale) / 2f
        return points.map { point ->
            point?.takeIf { it.x.isFinite() && it.y.isFinite() }?.let {
                PointF(offsetX + it.x.toFloat() * scale, offsetY + it.y.toFloat() * scale)
            }
        }
    }

    private fun matchParentLayoutParams() =
        LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )

    private val isDebuggable: Boolean
        get() =
            context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0

    private var lastDebugThumbnailMs = Long.MIN_VALUE

    override fun onDetachedFromWindow() {
        synchronized(this) {
            pendingHostFrame?.bitmap?.takeIf { !it.isRecycled }?.recycle()
            pendingHostFrame = null
        }
        hostImageView.setImageDrawable(null)
        displayedHostBitmap?.takeIf { !it.isRecycled }?.recycle()
        displayedHostBitmap = null
        super.onDetachedFromWindow()
    }

    private companion object {
        const val DEBUG_THUMBNAIL_INTERVAL_MS = 1_000L
        const val DEBUG_THUMBNAIL_WIDTH = 120
    }
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
    private var pipelineStatus = PosePipelineStatus.INITIALIZING
    private var debugThumbnail: Bitmap? = null
    private var hostPoseMode = false
    private var hostVideoFps = 0.0
    private var hostResultFps = 0.0
    private var lastHostMetricsUpdateMs = Long.MIN_VALUE

    fun update(next: SquatGuideDrawing?) {
        if (drawing == next) return
        drawing = next
        if (next != null) pipelineStatus = next.pipelineStatus
        invalidate()
    }

    fun updateStatus(next: PosePipelineStatus) {
        if (pipelineStatus == next) return
        pipelineStatus = next
        invalidate()
    }

    fun setHostPoseMode(enabled: Boolean) {
        if (hostPoseMode == enabled) return
        hostPoseMode = enabled
        invalidate()
    }

    fun updateHostMetrics(videoFps: Double, poseFps: Double) {
        if (!hostPoseMode) return
        val nowMs = SystemClock.elapsedRealtime()
        if (lastHostMetricsUpdateMs != Long.MIN_VALUE &&
            nowMs - lastHostMetricsUpdateMs < HOST_METRICS_INTERVAL_MS
        ) {
            return
        }
        lastHostMetricsUpdateMs = nowMs
        if (kotlin.math.abs(hostVideoFps - videoFps) < 0.1 &&
            kotlin.math.abs(hostResultFps - poseFps) < 0.1
        ) return
        hostVideoFps = videoFps
        hostResultFps = poseFps
        invalidate()
    }

    fun updateDebugThumbnail(next: Bitmap) {
        debugThumbnail?.takeIf { !it.isRecycled }?.recycle()
        debugThumbnail = next
        invalidate()
    }

    fun clearDebugThumbnail() {
        debugThumbnail?.takeIf { !it.isRecycled }?.recycle()
        debugThumbnail = null
        invalidate()
    }

    fun clear() {
        drawing = null
        pipelineStatus = PosePipelineStatus.INITIALIZING
        debugThumbnail?.takeIf { !it.isRecycled }?.recycle()
        debugThumbnail = null
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
            canvas.drawText(
                statusLabel(),
                inset,
                top + dp(30f),
                textPaint,
            )
            drawHostMetrics(canvas, inset, top)
            drawDebugThumbnail(canvas, inset, top)
            return
        }
        val pointPaint =
            if (current.pipelineStatus == PosePipelineStatus.VALID) {
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
            "${statusLabel()} / ${current.state.wireValue}",
            inset,
            max(top + dp(30f), dp(24f)),
            textPaint,
        )
        drawHostMetrics(canvas, inset, top)
        drawDebugThumbnail(canvas, inset, top)
    }

    private fun drawHostMetrics(
        canvas: Canvas,
        inset: Float,
        top: Float,
    ) {
        if (!hostPoseMode) return
        canvas.drawText(
            "Video FPS: ${String.format(java.util.Locale.US, "%.1f", hostVideoFps)}",
            inset,
            max(top + dp(50f), dp(44f)),
            textPaint,
        )
        canvas.drawText(
            "Pose FPS: ${String.format(java.util.Locale.US, "%.1f", hostResultFps)}",
            inset,
            max(top + dp(70f), dp(64f)),
            textPaint,
        )
    }

    private fun statusLabel(): String {
        if (!hostPoseMode) return pipelineStatus.displayLabel
        return when (pipelineStatus) {
            PosePipelineStatus.INITIALIZING -> "Host Pose: Connecting"
            PosePipelineStatus.FAILED -> "Host Pose: Disconnected"
            else -> "Host Pose: Ready"
        }
    }

    private fun drawDebugThumbnail(
        canvas: Canvas,
        inset: Float,
        top: Float,
    ) {
        debugThumbnail?.takeIf { !it.isRecycled }?.let { thumbnail ->
            val width = dp(96f)
            val height = width * thumbnail.height / thumbnail.width
            val destination =
                RectF(
                    this.width - inset - width,
                    top + dp(10f),
                    this.width - inset,
                    top + dp(10f) + height,
                )
            canvas.drawBitmap(thumbnail, null, destination, null)
            canvas.drawRect(destination, guidePaint)
        }
    }

    override fun onDetachedFromWindow() {
        debugThumbnail?.takeIf { !it.isRecycled }?.recycle()
        debugThumbnail = null
        super.onDetachedFromWindow()
    }

    private fun dp(value: Float): Float = value * resources.displayMetrics.density

    private companion object {
        const val HOST_METRICS_INTERVAL_MS = 1_000L
    }
}

private val PosePipelineStatus.displayLabel: String
    get() =
        when (this) {
            PosePipelineStatus.INITIALIZING -> "初期化中"
            PosePipelineStatus.AWAITING_RESULT -> "callback待機"
            PosePipelineStatus.NO_POSE -> "callbackあり・人物なし"
            PosePipelineStatus.HIP_UNAVAILABLE -> "腰なし"
            PosePipelineStatus.KNEE_UNAVAILABLE -> "膝なし"
            PosePipelineStatus.ANKLE_UNAVAILABLE -> "足首なし"
            PosePipelineStatus.CONFIDENCE_INSUFFICIENT -> "信頼度不足"
            PosePipelineStatus.VALID -> "検出"
            PosePipelineStatus.FAILED -> "推論エラー"
        }
