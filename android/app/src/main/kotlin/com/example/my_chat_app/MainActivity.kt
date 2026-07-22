package com.example.my_chat_app

import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "reollity/device",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSimulator" -> result.success(isEmulator())
                "canUseFullScreenIntent" -> result.success(canUseFullScreenIntent())
                "openFullScreenIntentSettings" -> {
                    openFullScreenIntentSettings()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "reollity/call_keep_alive",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val isVideo = call.argument<Boolean>("isVideo") == true
                    try {
                        result.success(CallForegroundService.start(this, isVideo))
                    } catch (error: Throwable) {
                        result.error(
                            "call_keep_alive_start_failed",
                            error.message ?: error.javaClass.simpleName,
                            null,
                        )
                    }
                }
                "stop" -> {
                    try {
                        CallForegroundService.stop(this)
                        result.success(true)
                    } catch (error: Throwable) {
                        result.error(
                            "call_keep_alive_stop_failed",
                            error.message ?: error.javaClass.simpleName,
                            null,
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun canUseFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT < 34) return true
        val manager = getSystemService(NotificationManager::class.java) ?: return true
        return manager.canUseFullScreenIntent()
    }

    private fun openFullScreenIntentSettings() {
        if (Build.VERSION.SDK_INT < 34) return
        val intent = Intent(
            Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
            Uri.parse("package:$packageName"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(intent)
        } catch (_: Throwable) {
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:$packageName"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }

    private fun isEmulator(): Boolean {
        val fingerprint = Build.FINGERPRINT.lowercase()
        val model = Build.MODEL.lowercase()
        val hardware = Build.HARDWARE.lowercase()
        val product = Build.PRODUCT.lowercase()
        return fingerprint.startsWith("generic") ||
            fingerprint.contains("emulator") ||
            fingerprint.contains("unknown") ||
            model.contains("google_sdk") ||
            model.contains("sdk_gphone") ||
            model.contains("emulator") ||
            model.contains("android sdk built for") ||
            hardware.contains("ranchu") ||
            hardware.contains("goldfish") ||
            product.contains("sdk") ||
            product.contains("emulator") ||
            product.contains("simulator")
    }
}
