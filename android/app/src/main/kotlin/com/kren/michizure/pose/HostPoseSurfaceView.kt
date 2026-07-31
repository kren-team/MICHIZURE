package com.kren.michizure.pose

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.view.SurfaceHolder
import android.view.SurfaceView
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.max

internal data class HostDisplayFrame(
    val frameId: Long,
    val payload: ByteArray,
    val jpegOffset: Int,
    val jpegLength: Int,
    val imageWidth: Int,
    val imageHeight: Int,
    val hip: PosePoint?,
    val knee: PosePoint?,
    val ankle: PosePoint?,
    val pipelineStatus: PosePipelineStatus,
)

internal enum class LatestFrameOffer {
    ACCEPTED,
    REPLACED,
    REJECTED_DISPOSED,
}

internal class LatestHostFrameSlot<T> {
    private val latest = AtomicReference<T?>(null)
    private val disposed = AtomicBoolean(false)

    fun offer(value: T): LatestFrameOffer {
        if (disposed.get()) return LatestFrameOffer.REJECTED_DISPOSED
        val previous = latest.getAndSet(value)
        if (disposed.get() && latest.compareAndSet(value, null)) {
            return LatestFrameOffer.REJECTED_DISPOSED
        }
        return if (previous == null) LatestFrameOffer.ACCEPTED else LatestFrameOffer.REPLACED
    }

    fun takeLatest(): T? = latest.getAndSet(null)

    fun clear(): T? = latest.getAndSet(null)

    fun dispose(): T? {
        disposed.set(true)
        return latest.getAndSet(null)
    }

    val size: Int
        get() = if (latest.get() == null) 0 else 1
}

internal interface HostPoseRenderListener {
    fun onDecoded(durationMs: Long)

    fun onDisplayed(drawDurationMs: Long)

    fun onDroppedBeforeDecode()

    fun onDroppedBeforeDraw()
}

internal class HostPoseSurfaceView(context: Context) :
    SurfaceView(context),
    SurfaceHolder.Callback {
    private val renderThread = HandlerThread("host-pose-surface").apply { start() }
    private val renderHandler = Handler(renderThread.looper)
    private val pending = LatestHostFrameSlot<HostDisplayFrame>()
    private val renderScheduled = AtomicBoolean(false)
    private val surfaceReady = AtomicBoolean(false)
    private val released = AtomicBoolean(false)
    private val bitmapOptions =
        BitmapFactory.Options().apply {
            inMutable = true
            inPreferredConfig = Bitmap.Config.RGB_565
        }
    private val bitmapPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val validPosePaint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(88, 214, 141)
            style = Paint.Style.STROKE
            strokeWidth = 4f * resources.displayMetrics.density
        }
    private val missingPosePaint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(255, 183, 77)
            style = Paint.Style.STROKE
            strokeWidth = 3f * resources.displayMetrics.density
        }
    @Volatile private var listener: HostPoseRenderListener? = null
    private var reusableBitmap: Bitmap? = null
    private var lastDrawMs = Long.MIN_VALUE

    init {
        holder.addCallback(this)
        setZOrderMediaOverlay(false)
    }

    fun setRenderListener(next: HostPoseRenderListener?) {
        listener = next
    }

    fun offer(frame: HostDisplayFrame): LatestFrameOffer {
        if (!surfaceReady.get() || released.get()) return LatestFrameOffer.REJECTED_DISPOSED
        val result = pending.offer(frame)
        scheduleRender()
        return result
    }

    fun clearFrame() {
        if (pending.clear() != null) listener?.onDroppedBeforeDecode()
        if (!released.get()) renderHandler.post(::clearSurface)
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        surfaceReady.set(true)
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) = Unit

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        surfaceReady.set(false)
        if (pending.clear() != null) listener?.onDroppedBeforeDecode()
    }

    fun release() {
        if (!released.compareAndSet(false, true)) return
        surfaceReady.set(false)
        if (pending.dispose() != null) listener?.onDroppedBeforeDecode()
        listener = null
        holder.removeCallback(this)
        renderHandler.removeCallbacksAndMessages(null)
        renderScheduled.set(false)
        renderHandler.post {
            reusableBitmap?.takeIf { !it.isRecycled }?.recycle()
            reusableBitmap = null
        }
        renderThread.quitSafely()
    }

    private fun scheduleRender() {
        if (released.get() || !renderScheduled.compareAndSet(false, true)) return
        renderHandler.post(::renderLatest)
    }

    private fun renderLatest() {
        if (released.get()) {
            renderScheduled.set(false)
            return
        }
        val now = SystemClock.elapsedRealtime()
        val delayMs =
            if (lastDrawMs == Long.MIN_VALUE) 0 else (FRAME_INTERVAL_MS - (now - lastDrawMs)).coerceAtLeast(0)
        if (delayMs > 0) {
            renderHandler.postDelayed(::renderLatest, delayMs)
            return
        }
        val frame = pending.takeLatest()
        if (frame != null) render(frame)
        renderScheduled.set(false)
        if (pending.size > 0) scheduleRender()
    }

    private fun render(frame: HostDisplayFrame) {
        if (!surfaceReady.get() || released.get()) {
            listener?.onDroppedBeforeDecode()
            return
        }
        val decodeStarted = SystemClock.elapsedRealtimeNanos()
        val bitmap = decode(frame)
        val decodeMs = nanosToMillis(SystemClock.elapsedRealtimeNanos() - decodeStarted)
        listener?.onDecoded(decodeMs)
        if (bitmap == null) {
            listener?.onDroppedBeforeDraw()
            return
        }
        val drawStarted = SystemClock.elapsedRealtimeNanos()
        val drawn = draw(frame, bitmap)
        val drawMs = nanosToMillis(SystemClock.elapsedRealtimeNanos() - drawStarted)
        lastDrawMs = SystemClock.elapsedRealtime()
        if (drawn) {
            listener?.onDisplayed(drawMs)
        } else {
            listener?.onDroppedBeforeDraw()
        }
    }

    private fun decode(frame: HostDisplayFrame): Bitmap? =
        runCatching { decodeWithReuse(frame) }.getOrNull()

    private fun decodeWithReuse(frame: HostDisplayFrame): Bitmap? {
        val candidate =
            reusableBitmap?.takeIf {
                !it.isRecycled && it.width == frame.imageWidth && it.height == frame.imageHeight
            }
        bitmapOptions.inBitmap = candidate
        val decoded =
            try {
                BitmapFactory.decodeByteArray(
                    frame.payload,
                    frame.jpegOffset,
                    frame.jpegLength,
                    bitmapOptions,
                )
            } catch (_: IllegalArgumentException) {
                bitmapOptions.inBitmap = null
                candidate?.recycle()
                reusableBitmap = null
                BitmapFactory.decodeByteArray(
                    frame.payload,
                    frame.jpegOffset,
                    frame.jpegLength,
                    bitmapOptions,
                )
            }
        if (decoded != null && decoded !== candidate) {
            candidate?.takeIf { !it.isRecycled }?.recycle()
        } else if (decoded == null) {
            candidate?.takeIf { !it.isRecycled }?.recycle()
        }
        if (decoded != null &&
            (decoded.width != frame.imageWidth || decoded.height != frame.imageHeight)
        ) {
            decoded.recycle()
            reusableBitmap = null
            return null
        }
        reusableBitmap = decoded
        return decoded
    }

    private fun draw(frame: HostDisplayFrame, bitmap: Bitmap): Boolean {
        if (!surfaceReady.get()) return false
        var canvas: Canvas? = null
        return try {
            canvas = runCatching { holder.lockHardwareCanvas() }.getOrNull() ?: holder.lockCanvas()
            canvas.drawColor(Color.BLACK)
            val scale = max(canvas.width.toFloat() / bitmap.width, canvas.height.toFloat() / bitmap.height)
            val left = (canvas.width - bitmap.width * scale) / 2f
            val top = (canvas.height - bitmap.height * scale) / 2f
            val destination = RectF(left, top, left + bitmap.width * scale, top + bitmap.height * scale)
            canvas.drawBitmap(bitmap, null, destination, bitmapPaint)
            drawPose(canvas, frame, scale, left, top)
            true
        } catch (_: RuntimeException) {
            false
        } finally {
            canvas?.let { locked -> runCatching { holder.unlockCanvasAndPost(locked) } }
        }
    }

    private fun drawPose(
        canvas: Canvas,
        frame: HostDisplayFrame,
        scale: Float,
        left: Float,
        top: Float,
    ) {
        val paint =
            if (frame.pipelineStatus == PosePipelineStatus.VALID) validPosePaint else missingPosePaint
        fun mapped(point: PosePoint?) =
            point?.takeIf { it.x.isFinite() && it.y.isFinite() }?.let {
                android.graphics.PointF(left + it.x.toFloat() * scale, top + it.y.toFloat() * scale)
            }
        val hip = mapped(frame.hip)
        val knee = mapped(frame.knee)
        val ankle = mapped(frame.ankle)
        listOfNotNull(hip, knee, ankle).forEach {
            canvas.drawCircle(it.x, it.y, POINT_RADIUS_DP * resources.displayMetrics.density, paint)
        }
        if (hip != null && knee != null) canvas.drawLine(hip.x, hip.y, knee.x, knee.y, paint)
        if (knee != null && ankle != null) canvas.drawLine(knee.x, knee.y, ankle.x, ankle.y, paint)
    }

    private fun clearSurface() {
        if (!surfaceReady.get()) return
        var canvas: Canvas? = null
        try {
            canvas = holder.lockCanvas()
            canvas.drawColor(Color.BLACK)
        } catch (_: RuntimeException) {
            // The surface can disappear between the readiness check and lockCanvas.
        } finally {
            canvas?.let { locked -> runCatching { holder.unlockCanvasAndPost(locked) } }
        }
    }

    private fun nanosToMillis(value: Long): Long = value.coerceAtLeast(0) / 1_000_000L

    private companion object {
        const val MAX_RENDER_FPS = 12
        const val FRAME_INTERVAL_MS = 1_000L / MAX_RENDER_FPS
        const val POINT_RADIUS_DP = 7f
    }
}
