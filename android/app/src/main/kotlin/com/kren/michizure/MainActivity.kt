package com.kren.michizure

import com.kren.michizure.platform.DeviceControlContract
import com.kren.michizure.platform.DeviceControlMethodHandler
import com.kren.michizure.platform.TaskEventContract
import com.kren.michizure.platform.TaskEventStreamHandler
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var deviceControlChannel: MethodChannel? = null
    private var deviceControlHandler: DeviceControlMethodHandler? = null
    private var taskEventChannel: EventChannel? = null
    private var taskEventHandler: TaskEventStreamHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        deviceControlHandler = DeviceControlMethodHandler(applicationContext)
        deviceControlChannel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                DeviceControlContract.CHANNEL_NAME,
            ).also {
                it.setMethodCallHandler(deviceControlHandler)
            }
        taskEventHandler = TaskEventStreamHandler(applicationContext)
        taskEventChannel =
            EventChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                TaskEventContract.CHANNEL_NAME,
            ).also {
                it.setStreamHandler(taskEventHandler)
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        deviceControlChannel?.setMethodCallHandler(null)
        deviceControlChannel = null
        deviceControlHandler?.close()
        deviceControlHandler = null
        taskEventChannel?.setStreamHandler(null)
        taskEventChannel = null
        taskEventHandler?.close()
        taskEventHandler = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
