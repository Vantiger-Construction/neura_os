package com.neurocompanion.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var localSpeechInput: NeuraLocalSpeechInput? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        localSpeechInput = NeuraLocalSpeechInput(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onPause() {
        localSpeechInput?.stop()
        super.onPause()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        localSpeechInput?.dispose()
        localSpeechInput = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
