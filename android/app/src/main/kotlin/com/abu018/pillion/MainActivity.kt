package com.abu018.pillion

import com.abu018.pillion.ride.RideController
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        RideController.register(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}
