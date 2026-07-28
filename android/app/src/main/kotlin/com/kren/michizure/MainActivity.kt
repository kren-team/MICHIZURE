package com.kren.michizure

import com.kren.michizure.platform.DeviceControlContract
import com.kren.michizure.platform.DeviceControlMethodHandler
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var deviceControlChannel: MethodChannel? = null
    private var deviceControlHandler: DeviceControlMethodHandler? = null

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
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        deviceControlChannel?.setMethodCallHandler(null)
        deviceControlChannel = null
        deviceControlHandler?.close()
        deviceControlHandler = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
