package com.kren.michizure

import com.kren.michizure.platform.DeviceControlContract
import com.kren.michizure.platform.DeviceControlMethodHandler
import com.kren.michizure.platform.TaskEventContract
import com.kren.michizure.platform.TaskEventStreamHandler
import com.kren.michizure.pose.PosePreviewFactory
import com.kren.michizure.pose.SquatContract
import com.kren.michizure.pose.SquatEventStreamHandler
import com.kren.michizure.pose.SquatMethodHandler
import com.kren.michizure.pose.SquatSessionManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec

class MainActivity : FlutterActivity() {
    private var deviceControlChannel: MethodChannel? = null
    private var deviceControlHandler: DeviceControlMethodHandler? = null
    private var taskEventChannel: EventChannel? = null
    private var taskEventHandler: TaskEventStreamHandler? = null
    private var squatMethodChannel: MethodChannel? = null
    private var squatMethodHandler: SquatMethodHandler? = null
    private var squatEventChannel: EventChannel? = null
    private var squatEventHandler: SquatEventStreamHandler? = null
    private var squatSessionManager: SquatSessionManager? = null

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
        squatSessionManager = SquatSessionManager(this)
        squatMethodHandler =
            SquatMethodHandler(this, requireNotNull(squatSessionManager))
        squatMethodChannel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                SquatContract.METHOD_CHANNEL,
            ).also {
                it.setMethodCallHandler(squatMethodHandler)
            }
        squatEventHandler = SquatEventStreamHandler()
        squatEventChannel =
            EventChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                SquatContract.EVENT_CHANNEL,
            ).also {
                it.setStreamHandler(squatEventHandler)
            }
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                SquatContract.PREVIEW_VIEW_TYPE,
                PosePreviewFactory(
                    requireNotNull(squatSessionManager),
                    StandardMessageCodec.INSTANCE,
                ),
            )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (squatMethodHandler?.onRequestPermissionsResult(
                requestCode,
                permissions,
                grantResults,
            ) == true
        ) {
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
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
        squatMethodChannel?.setMethodCallHandler(null)
        squatMethodChannel = null
        squatMethodHandler?.close()
        squatMethodHandler = null
        squatEventChannel?.setStreamHandler(null)
        squatEventChannel = null
        squatEventHandler?.close()
        squatEventHandler = null
        squatSessionManager?.close()
        squatSessionManager = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
