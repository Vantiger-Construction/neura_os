package com.neurocompanion.app

import android.app.Activity
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** No platform-health classes are loaded on the retained Android 24-33 path. */
class NeuraHealthConnectBridge(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "neura/health_connect")
    private var reader: NeuraHealthReader? = null
    private var initialized = false
    private var foreground = false

    private fun initialize() {
        if (initialized) return
        initialized = true
        if (Build.VERSION.SDK_INT >= 34) {
            // A missing/broken optional health service must never break app startup.
            reader = try { NeuraPlatformHealthReader(activity) } catch (_: Exception) { null }
            if (foreground) reader?.onResume()
        }
    }

    init { channel.setMethodCallHandler(this) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "cancel") {
            val current = reader
            if (current == null) result.success(null) else current.handle(call, result)
            return
        }
        if (!foreground) {
            result.error("unavailable", "The foreground app is required.", null)
            return
        }
        initialize()
        if (call.method == "availability") {
            result.success(mapOf("available" to (reader?.available == true), "minimumAndroid" to 34))
        } else if (reader == null) {
            result.error("unavailable", "Android 14 or newer is required for this connector.", null)
        } else reader!!.handle(call, result)
    }

    fun onResume() { foreground = true; reader?.onResume() }
    fun onPause() { foreground = false; reader?.onPause() }
    fun onPermissionsResult(code: Int): Boolean = reader?.onPermissionsResult(code) ?: false
    fun dispose() {
        reader?.dispose()
        channel.setMethodCallHandler(null)
    }
}

internal interface NeuraHealthReader {
    val available: Boolean
    fun handle(call: MethodCall, result: MethodChannel.Result)
    fun onResume()
    fun onPause()
    fun onPermissionsResult(code: Int): Boolean
    fun dispose()
}
