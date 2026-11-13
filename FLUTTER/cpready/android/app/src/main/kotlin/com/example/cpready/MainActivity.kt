
package com.example.cpready

import android.media.AudioAttributes
import android.media.SoundPool
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "cpready/metronome"
    private val mainHandler = Handler(Looper.getMainLooper())

    private var soundPool: SoundPool? = null
    private var soundId = 0
    private var loaded = false
    private var pendingLoad: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "preload" -> preloadSound(result)

                "tick" -> {
                    if (loaded && soundId != 0) {
                        soundPool?.play(
                            soundId,
                            1.0f,
                            1.0f,
                            1,
                            0,
                            1.0f
                        )
                    }
                    result.success(null)
                }

                "stop" -> {
                    // Each click finishes naturally.
                    result.success(null)
                }

                "dispose" -> {
                    releaseSound()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun preloadSound(result: MethodChannel.Result) {
        if (loaded) {
            result.success(null)
            return
        }

        if (pendingLoad != null) {
            result.error(
                "LOAD_IN_PROGRESS",
                "Metronome is already loading",
                null
            )
            return
        }

        pendingLoad = result

        try {
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()

            val pool = SoundPool.Builder()
                .setMaxStreams(2)
                .setAudioAttributes(attributes)
                .build()

            soundPool = pool

            pool.setOnLoadCompleteListener { completedPool, id, status ->
                mainHandler.post {
                    if (soundPool !== completedPool) return@post

                    val callback = pendingLoad
                    pendingLoad = null

                    if (status == 0 && id == soundId) {
                        loaded = true
                        callback?.success(null)
                    } else {
                        callback?.error(
                            "LOAD_FAILED",
                            "Unable to load metronome WAV: $status",
                            null
                        )
                        releaseSound()
                    }
                }
            }



            val assetPath = io.flutter.FlutterInjector.instance()
                .flutterLoader()
                .getLookupKeyForAsset(
                    "assets/audio/metronome_tick.wav"
                )



            assets.openFd(assetPath).use { descriptor ->
                soundId = pool.load(descriptor, 1)
            }

            if (soundId == 0) {
                pendingLoad = null
                result.error(
                    "LOAD_FAILED",
                    "SoundPool rejected the WAV file",
                    null
                )
                releaseSound()
            }

        } catch (error: Exception) {
            pendingLoad = null
            releaseSound()
            result.error(
                "LOAD_ERROR",
                error.message,
                null
            )
        }
    }

    private fun releaseSound() {
        pendingLoad?.error(
            "DISPOSED",
            "Metronome was disposed while loading",
            null
        )
        pendingLoad = null
        loaded = false
        soundId = 0
        soundPool?.release()
        soundPool = null
    }

    override fun onDestroy() {
        releaseSound()
        super.onDestroy()
    }
}
