package com.neurocompanion.app

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** API 31+ on-device recognition only. No default recognizer or downloads. */
class NeuraLocalSpeechInput(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "neura/local_speech_input")
    private var recognizer: SpeechRecognizer? = null
    private var session = 0L
    private var listening = false
    private var text = ""
    private var finalResult = false

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "isAvailable" -> result.success(available())
                    "start" -> {
                        val id = (call.argument<Number>("session"))?.toLong() ?: 0L
                        start(id)
                        result.success(true)
                    }
                    "stop" -> {
                        val id = (call.argument<Number>("session"))?.toLong() ?: 0L
                        if (id >= session) stop()
                        result.success(null)
                    }
                    "poll" -> {
                        val id = (call.argument<Number>("session"))?.toLong() ?: 0L
                        if (!activity.hasWindowFocus()) stop()
                        val current = id == session
                        result.success(mapOf("session" to id,
                            "listening" to (current && listening),
                            "text" to if (current) text else "",
                            "final" to (current && finalResult)))
                        if (current) { text = ""; finalResult = false }
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                stop()
                result.error("local_speech_unavailable", "Local speech input is unavailable.", null)
            }
        }
    }

    private fun available() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
        SpeechRecognizer.isOnDeviceRecognitionAvailable(activity)

    private fun start(id: Long) {
        stop()
        check(id > 0 && activity.hasWindowFocus() && available())
        check(activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) error("Local speech unavailable")
        val engine = SpeechRecognizer.createOnDeviceSpeechRecognizer(activity)
        recognizer = engine
        session = id
        listening = true
        engine.setRecognitionListener(object : RecognitionListener {
            private fun current() = session == id && recognizer === engine && listening
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
            override fun onError(error: Int) {
                if (current()) { listening = false; text = ""; finalResult = false }
            }
            override fun onPartialResults(partialResults: Bundle?) {
                if (current()) text = words(partialResults)
            }
            override fun onResults(results: Bundle?) {
                if (!current()) return
                text = words(results)
                finalResult = text.isNotBlank()
                listening = false
            }
        })
        engine.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        })
    }

    private fun words(bundle: Bundle?): String =
        bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
            ?.takeIf { it.length <= 16384 && !it.contains('\u0000') } ?: ""

    fun stop() {
        listening = false
        session = 0
        text = ""
        finalResult = false
        val engine = recognizer
        recognizer = null // Invalidate callbacks before cancelling/destroying.
        try { engine?.cancel() } finally { engine?.destroy() }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        stop()
    }
}
