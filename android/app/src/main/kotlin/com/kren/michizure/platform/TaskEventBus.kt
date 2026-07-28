package com.kren.michizure.platform

import android.os.Handler
import android.os.Looper
import com.kren.michizure.persistence.NativeTaskEvent
import io.flutter.plugin.common.EventChannel

object TaskEventBus {
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var sink: EventChannel.EventSink? = null

    fun attach(eventSink: EventChannel.EventSink) {
        sink = eventSink
    }

    fun detach() {
        sink = null
    }

    fun emit(event: NativeTaskEvent) {
        mainHandler.post {
            sink?.success(event.toWirePayload())
        }
    }
}
