package com.kren.michizure.pose

import io.flutter.plugin.common.EventChannel

class SquatEventStreamHandler : EventChannel.StreamHandler {
    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink,
    ) {
        if (!SquatContract.supports(arguments)) {
            events.error(
                SquatContract.ERROR_CONTRACT_MISMATCH,
                "The squat event contract version is unsupported.",
                SquatContract.versioned(),
            )
            return
        }
        SquatEventBus.setListener(events::success)
    }

    override fun onCancel(arguments: Any?) {
        SquatEventBus.setListener(null)
    }

    fun close() {
        SquatEventBus.setListener(null)
    }
}
