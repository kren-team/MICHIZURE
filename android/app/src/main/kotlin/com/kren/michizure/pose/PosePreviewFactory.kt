package com.kren.michizure.pose

import android.content.Context
import android.view.View
import io.flutter.plugin.common.MessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class PosePreviewFactory(
    private val manager: SquatSessionManager,
    codec: MessageCodec<Any>,
) : PlatformViewFactory(codec) {
    override fun create(
        context: Context,
        viewId: Int,
        args: Any?,
    ): PlatformView = PosePreviewView(context, manager)
}

private class PosePreviewView(
    context: Context,
    private val manager: SquatSessionManager,
) : PlatformView {
    private val cameraContainer = SquatCameraContainer(context)

    init {
        manager.attachPreview(cameraContainer)
    }

    override fun getView(): View = cameraContainer

    override fun dispose() {
        manager.detachPreview(cameraContainer)
    }
}
