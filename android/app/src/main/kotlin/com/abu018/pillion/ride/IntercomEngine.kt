package com.abu018.pillion.ride

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.NoiseSuppressor
import android.os.Process
import android.os.SystemClock

/**
 * Phone mic -> headsets intercom with automatic music ducking.
 *
 * Voice is captured from the built-in mic, high-pass filtered (wind rumble),
 * gated by [VoiceGate], and played as media so it follows the phone's current
 * media output (including Samsung Dual Audio to two headsets). While someone
 * speaks, a transient "may duck" audio focus request makes Android lower other
 * apps' music (Spotify, YouTube Music, ...); it is released after
 * [musicReturnDelayMs] of silence.
 */
class IntercomEngine(
    context: Context,
    private val onState: (Map<String, Any?>) -> Unit,
    private val onStopped: () -> Unit,
) {
    @Volatile var sensitivity = 0.4
    @Volatile var voiceGain = 2.0f
    @Volatile var musicReturnDelayMs = 1500L
    @Volatile var duckMusic = true

    /**
     * Address of the only headset that should hear the voice, so the person
     * talking into the phone doesn't hear themselves. Null sends it to every
     * media output.
     */
    @Volatile var voiceTargetAddress: String? = null
        set(value) {
            if (field != value) routeDirty = true
            field = value
        }

    val running: Boolean get() = thread != null

    private val audioManager = context.getSystemService(AudioManager::class.java)
    private val gate = VoiceGate()
    @Volatile private var thread: Thread? = null
    @Volatile private var stopRequested = false
    @Volatile private var routeDirty = true
    private var voiceRoute: String? = null
    private var focusRequest: AudioFocusRequest? = null
    private var focusHeld = false

    fun start() {
        if (thread != null) return
        stopRequested = false
        val worker = Thread({
            try {
                loop()
            } finally {
                thread = null
                onStopped()
            }
        }, "pillion-intercom")
        thread = worker
        worker.start()
    }

    /** Re-resolve [voiceTargetAddress], e.g. after a headset reconnects. */
    fun refreshRoute() {
        routeDirty = true
    }

    fun stop() {
        stopRequested = true
        thread?.join(1000)
        thread = null
    }

    @SuppressLint("MissingPermission")
    private fun loop() {
        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)

        val recordMin = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val trackMin = AudioTrack.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (recordMin <= 0 || trackMin <= 0) {
            fail("This phone doesn't support the intercom audio format.")
            return
        }

        val record: AudioRecord
        try {
            record = AudioRecord.Builder()
                .setAudioSource(MediaRecorder.AudioSource.MIC)
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(SAMPLE_RATE)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                        .build()
                )
                .setBufferSizeInBytes(maxOf(recordMin, FRAME * 2 * 4))
                .build()
        } catch (e: Exception) {
            fail("Could not open the microphone: ${e.message}")
            return
        }
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            fail("Could not open the microphone. Is another app using it?")
            return
        }
        // Headset mics would force call mode (and break music), so always use the phone mic.
        audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
            .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_MIC }
            ?.let { record.preferredDevice = it }
        val noiseSuppressor = if (NoiseSuppressor.isAvailable()) NoiseSuppressor.create(record.audioSessionId) else null
        noiseSuppressor?.enabled = true

        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(SAMPLE_RATE)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(maxOf(trackMin, FRAME * 2 * 2))
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            .build()

        gate.reset()
        val input = ShortArray(FRAME)
        val output = ShortArray(FRAME)
        val preRoll = ArrayDeque<ShortArray>()
        var gateOpen = false
        var gateGain = 0f
        var lastSpeechAt = 0L
        var lastEmitAt = 0L
        var hpPrevIn = 0f
        var hpPrevOut = 0f

        try {
            record.startRecording()
            track.play()
            emit(gateOpen = false, error = null)

            while (!stopRequested) {
                if (routeDirty) {
                    routeDirty = false
                    applyVoiceRoute(track)
                }
                val read = record.read(input, 0, FRAME)
                if (read < 0) {
                    fail("The microphone stopped (error $read).")
                    break
                }
                if (read == 0) continue

                // One-pole high-pass (~150 Hz) to cut wind and engine rumble.
                for (i in 0 until read) {
                    val x = input[i].toFloat()
                    val y = HP_ALPHA * (hpPrevOut + x - hpPrevIn)
                    hpPrevIn = x
                    hpPrevOut = y
                    input[i] = y.toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                }

                gate.sensitivity = sensitivity
                val speech = gate.process(input, read)
                val now = SystemClock.elapsedRealtime()

                if (speech) {
                    lastSpeechAt = now
                    if (!gateOpen) {
                        gateOpen = true
                        requestDuck()
                        // Replay the frames that triggered detection so word onsets aren't lost.
                        for (frame in preRoll) writeScaled(track, frame, frame.size, output, voiceGain, 1f)
                        preRoll.clear()
                    }
                } else if (gateOpen && now - lastSpeechAt > VOICE_HANGOVER_MS) {
                    gateOpen = false
                }
                if (!gateOpen && focusHeld && now - lastSpeechAt > musicReturnDelayMs) {
                    releaseDuck()
                }

                val target = if (gateOpen) 1f else 0f
                if (gateOpen || gateGain > 0f) {
                    gateGain = rampTowards(gateGain, target)
                    writeScaled(track, input, read, output, voiceGain, gateGain)
                } else {
                    preRoll.addLast(input.copyOf(read))
                    if (preRoll.size > PRE_ROLL_FRAMES) preRoll.removeFirst()
                    output.fill(0.toShort(), 0, read)
                    track.write(output, 0, read)
                }

                if (now - lastEmitAt >= 100) {
                    lastEmitAt = now
                    emit(gateOpen, null)
                }
            }
        } catch (e: Exception) {
            fail("Intercom stopped: ${e.message}")
        } finally {
            releaseDuck()
            try { record.stop() } catch (_: Exception) {}
            record.release()
            noiseSuppressor?.release()
            try { track.stop() } catch (_: Exception) {}
            track.release()
            onState(mapOf("running" to false, "speaking" to false, "ducking" to false, "level" to 0.0))
        }
    }

    private fun applyVoiceRoute(track: AudioTrack) {
        val address = voiceTargetAddress
        val device = address?.let { wanted ->
            audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull {
                it.address.equals(wanted, ignoreCase = true) && it.type in HEADSET_TYPES
            }
        }
        track.preferredDevice = device
        voiceRoute = device?.productName?.toString()
    }

    private fun writeScaled(track: AudioTrack, src: ShortArray, length: Int, out: ShortArray, gain: Float, envelope: Float) {
        val g = gain * envelope
        for (i in 0 until length) {
            out[i] = (src[i] * g).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
        }
        track.write(out, 0, length)
    }

    private fun rampTowards(value: Float, target: Float): Float {
        val step = 1f / RAMP_FRAMES
        return if (value < target) minOf(target, value + step) else maxOf(target, value - step)
    }

    private fun requestDuck() {
        if (!duckMusic || focusHeld) return
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setOnAudioFocusChangeListener { }
            .build()
        focusHeld = audioManager.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        focusRequest = request
    }

    private fun releaseDuck() {
        focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        focusRequest = null
        focusHeld = false
    }

    private fun emit(gateOpen: Boolean, error: String?) {
        onState(
            mapOf(
                "running" to true,
                "speaking" to gateOpen,
                "ducking" to focusHeld,
                "level" to gate.meterLevel,
                "noiseFloorDb" to gate.noiseFloorDb,
                "voiceRoute" to voiceRoute,
                "error" to error,
            )
        )
    }

    private fun fail(message: String) {
        onState(mapOf("running" to false, "speaking" to false, "ducking" to false, "level" to 0.0, "error" to message))
    }

    private companion object {
        const val SAMPLE_RATE = 16000
        const val FRAME = 320 // 20 ms
        const val PRE_ROLL_FRAMES = 3
        const val RAMP_FRAMES = 3
        const val VOICE_HANGOVER_MS = 350L
        const val HP_ALPHA = 0.944f // ~150 Hz at 16 kHz
        val HEADSET_TYPES = setOf(
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_BLE_SPEAKER,
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_USB_HEADSET,
        )
    }
}
