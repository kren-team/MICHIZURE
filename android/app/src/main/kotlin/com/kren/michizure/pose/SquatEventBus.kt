package com.kren.michizure.pose

import android.os.Handler
import android.os.Looper

object SquatEventBus {
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var listener: ((Map<String, Any?>) -> Unit)? = null

    fun setListener(value: ((Map<String, Any?>) -> Unit)?) {
        listener = value
    }

    fun emit(event: Map<String, Any?>) {
        mainHandler.post { listener?.invoke(event) }
    }
}
