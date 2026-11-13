package com.abu018.pillion.ride

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Bridges Ride mode between Flutter and the native intercom. */
object RideController : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private const val METHODS = "pillion/ride"
    private const val EVENTS = "pillion/ride/events"

    private val main = Handler(Looper.getMainLooper())
    private var appContext: Context? = null
    private var engine: IntercomEngine? = null
    private var sink: EventChannel.EventSink? = null
    private var lastState: Map<String, Any?> = mapOf("running" to false)
    private var deviceCallbackRegistered = false

    fun register(context: Context, messenger: BinaryMessenger) {
        appContext = context.applicationContext
        MethodChannel(messenger, METHODS).setMethodCallHandler(this)
        EventChannel(messenger, EVENTS).setStreamHandler(this)
        registerDeviceCallback(context.applicationContext)
    }

    fun engine(context: Context): IntercomEngine =
        engine ?: IntercomEngine(
            context.applicationContext,
            onState = { state ->
                main.post {
                    lastState = state
                    sink?.success(mapOf("type" to "state") + state)
                }
            },
            onStopped = {
                main.post {
                    if (engine?.running != true) RideService.stop(context.applicationContext)
                }
            },
        ).also { engine = it }

    fun stop(context: Context) {
        RideService.stop(context)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = appContext ?: return result.error("no_context", "Not attached", null)
        when (call.method) {
            "getOutputs" -> result.success(outputs(context))
            "configure" -> {
                val e = engine(context)
                call.argument<Double>("sensitivity")?.let { e.sensitivity = it }
                call.argument<Double>("voiceGain")?.let { e.voiceGain = it.toFloat() }
                call.argument<Int>("musicReturnDelayMs")?.let { e.musicReturnDelayMs = it.toLong() }
                call.argument<Boolean>("duckMusic")?.let { e.duckMusic = it }
                if (call.hasArgument("voiceTarget")) e.voiceTargetAddress = call.argument<String>("voiceTarget")
                result.success(null)
            }
            "start" -> {
                RideService.start(context)
                result.success(null)
            }
            "stop" -> {
                RideService.stop(context)
                result.success(null)
            }
            "state" -> result.success(lastState)
            "openBluetoothSettings" -> {
                launch(context, Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                result.success(null)
            }
            "launchApp" -> {
                val pkg = call.argument<String>("package") ?: return result.error("arg", "package missing", null)
                val intent = context.packageManager.getLaunchIntentForPackage(pkg)
                if (intent == null) {
                    result.success(false)
                } else {
                    result.success(launch(context, intent))
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        events?.success(mapOf("type" to "state") + lastState)
        appContext?.let { events?.success(mapOf("type" to "outputs", "outputs" to outputs(it))) }
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private fun launch(context: Context, intent: Intent): Boolean = try {
        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (_: ActivityNotFoundException) {
        false
    }

    private fun registerDeviceCallback(context: Context) {
        if (deviceCallbackRegistered) return
        deviceCallbackRegistered = true
        context.getSystemService(AudioManager::class.java).registerAudioDeviceCallback(object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) = pushOutputs(context)
            override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) = pushOutputs(context)
        }, main)
    }

    private fun pushOutputs(context: Context) {
        engine?.refreshRoute()
        sink?.success(mapOf("type" to "outputs", "outputs" to outputs(context)))
    }

    /** Connected headphone-type outputs (Bluetooth, LE Audio, wired, USB). */
    private fun outputs(context: Context): List<Map<String, Any?>> {
        val manager = context.getSystemService(AudioManager::class.java)
        val seen = mutableSetOf<String>()
        return manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).mapNotNull { device ->
            val kind = when (device.type) {
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "bluetooth"
                AudioDeviceInfo.TYPE_BLE_HEADSET, AudioDeviceInfo.TYPE_BLE_SPEAKER -> "le_audio"
                AudioDeviceInfo.TYPE_BLE_BROADCAST -> "broadcast"
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET -> "wired"
                AudioDeviceInfo.TYPE_USB_HEADSET -> "usb"
                else -> null
            } ?: return@mapNotNull null
            val name = device.productName?.toString()?.takeIf { it.isNotBlank() } ?: "Headset"
            val key = "$kind:${device.address}:$name"
            if (!seen.add(key)) return@mapNotNull null
            mapOf("name" to name, "kind" to kind, "address" to device.address)
        }
    }
}
