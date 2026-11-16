package com.neurocompanion.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var localSpeechInput: NeuraLocalSpeechInput? = null
    private var healthReader: NeuraHealthConnectBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        localSpeechInput = NeuraLocalSpeechInput(this, flutterEngine.dartExecutor.binaryMessenger)
        healthReader = NeuraHealthConnectBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onResume() {
        super.onResume()
        healthReader?.onResume()
    }

    override fun onPause() {
        localSpeechInput?.stop()
        healthReader?.onPause()
        super.onPause()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        healthReader?.dispose()
        healthReader = null
        localSpeechInput?.dispose()
        localSpeechInput = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (healthReader?.onPermissionsResult(requestCode) == true) return
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
