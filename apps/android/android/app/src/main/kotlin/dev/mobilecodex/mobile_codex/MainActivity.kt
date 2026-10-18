package dev.mobilecodex.mobile_codex

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private companion object {
        const val DEVICE_CHANNEL = "mobile_codex/device"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != "model") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val manufacturer = Build.MANUFACTURER.trim()
                val model = Build.MODEL.trim()
                val hardware = listOf(manufacturer, model)
                    .filter { it.isNotEmpty() }
                    .distinct()
                    .joinToString(" ")
                val release = Build.VERSION.RELEASE?.trim().orEmpty()
                val version = if (release.isEmpty()) {
                    "SDK ${Build.VERSION.SDK_INT}"
                } else {
                    "Android $release; SDK ${Build.VERSION.SDK_INT}"
                }
                result.success(listOf(hardware.ifEmpty { "Android device" }, "($version)").joinToString(" "))
            }
    }
}
