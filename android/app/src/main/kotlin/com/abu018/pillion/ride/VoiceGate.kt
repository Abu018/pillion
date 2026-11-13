package com.abu018.pillion.ride

import kotlin.math.log10
import kotlin.math.sqrt

/**
 * Energy-based speech detector for 20 ms frames of 16-bit mono PCM.
 *
 * Mirrors the Dart VadDetector but reacts faster (3 of the last 5 frames), since
 * here it gates live voice and late activation clips the start of words.
 */
class VoiceGate {
    var sensitivity = 0.5

    var noiseFloorDb = -60.0
        private set
    var levelDb = -90.0
        private set

    private val window = ArrayDeque<Boolean>()

    /** 0..1 level for a meter. */
    val meterLevel: Double get() = ((levelDb + 70) / 60).coerceIn(0.0, 1.0)

    /** Returns true if recent frames contain speech. */
    fun process(frame: ShortArray, length: Int): Boolean {
        var sumSquares = 0.0
        var zeroCrossings = 0
        for (i in 0 until length) {
            val s = frame[i].toDouble()
            sumSquares += s * s
            if (i > 0 && (frame[i] >= 0) != (frame[i - 1] >= 0)) zeroCrossings++
        }
        val rms = sqrt(sumSquares / length) / 32768.0
        levelDb = 20 * log10(rms + 1e-9)
        val zcr = zeroCrossings.toDouble() / length

        val margin = 18 - 12 * sensitivity
        val minAbsolute = -50 - 10 * sensitivity
        val speechFrame = levelDb > noiseFloorDb + margin &&
            levelDb > minAbsolute &&
            zcr > 0.01 && zcr < 0.5

        noiseFloorDb += if (levelDb < noiseFloorDb) {
            (levelDb - noiseFloorDb) * 0.2
        } else {
            (levelDb - noiseFloorDb) * (if (speechFrame) 0.002 else 0.02)
        }
        noiseFloorDb = noiseFloorDb.coerceIn(-90.0, -15.0)

        window.addLast(speechFrame)
        if (window.size > WINDOW) window.removeFirst()
        return window.count { it } >= ACTIVATION
    }

    fun reset() {
        window.clear()
        noiseFloorDb = -60.0
        levelDb = -90.0
    }

    private companion object {
        const val WINDOW = 5
        const val ACTIVATION = 3
    }
}
