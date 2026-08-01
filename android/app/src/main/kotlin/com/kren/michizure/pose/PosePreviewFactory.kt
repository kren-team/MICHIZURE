package com.kren.michizure.pose

import android.content.Context
import android.view.View
import io.flutter.plugin.common.MessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.util.concurrent.atomic.AtomicBoolean

class PosePreviewFactory(
    private val manager: SquatSessionManager,
    codec: MessageCodec<Any>,
) : PlatformViewFactory(codec) {
    override fun create(
        context: Context,
        viewId: Int,
        args: Any?,
    ): PlatformView = PosePreviewView(context, manager, PoseSourceMode.fromCreationParams(args))
}

private class PosePreviewView(
    context: Context,
    private val manager: SquatSessionManager,
    mode: PoseSourceMode,
) : PlatformView {
    private val disposed = AtomicBoolean(false)
    private val cameraContainer =
        SquatCameraContainer(context, initialHostPoseMode = mode == PoseSourceMode.HOST_DEMO)

    init {
        manager.attachPreview(cameraContainer, mode)
    }

    override fun getView(): View = cameraContainer

    override fun dispose() {
        if (!disposed.compareAndSet(false, true)) return
        manager.detachPreview(cameraContainer)
        cameraContainer.releaseHostRenderer()
    }
}
