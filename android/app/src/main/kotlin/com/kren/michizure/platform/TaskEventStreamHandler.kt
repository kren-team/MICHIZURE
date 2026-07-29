package com.kren.michizure.platform

import android.content.Context
import com.kren.michizure.persistence.NativeTaskStore
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class TaskEventStreamHandler(
    context: Context,
    private val store: NativeTaskStore = NativeTaskStore(context),
) : EventChannel.StreamHandler {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val payload = arguments as? Map<*, *>
        if (payload?.get("contractVersion") != TaskEventContract.CONTRACT_VERSION) {
            events.error(
                DeviceControlContract.ERROR_CHANNEL_CONTRACT_MISMATCH,
                "The app and Android event bridge versions do not match.",
                DeviceControlContract.versionedPayload(),
            )
            return
        }
        TaskEventBus.attach(events)
        scope.launch {
            runCatching { store.readPendingEvent() }
                .onSuccess { event ->
                    if (event != null) {
                        TaskEventBus.emit(event)
                    }
                }
                .onFailure {
                    TaskEventBus.emitError(
                        DeviceControlContract.ERROR_NATIVE_STATE_CORRUPT,
                        "The pending task event could not be read.",
                        DeviceControlContract.versionedPayload(),
                    )
                }
        }
    }

    override fun onCancel(arguments: Any?) {
        TaskEventBus.detach()
    }

    fun close() {
        TaskEventBus.detach()
        scope.cancel()
    }
}
