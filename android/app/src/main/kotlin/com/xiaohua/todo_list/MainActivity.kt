package com.xiaohua.todo_list

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val OPEN_JSON_REQUEST = 901
        private const val SAVE_JSON_REQUEST = 902
    }

    private var pendingOpenResult: MethodChannel.Result? = null
    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingSaveContent: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "todo_list/backup_files")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickJson" -> {
                        if (pendingOpenResult != null) {
                            result.error("busy", "A file picker is already open", null)
                        } else {
                            pendingOpenResult = result
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "application/json"
                                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/plain"))
                            }
                            startActivityForResult(intent, OPEN_JSON_REQUEST)
                        }
                    }
                    "saveJson" -> {
                        if (pendingSaveResult != null) {
                            result.error("busy", "A file picker is already open", null)
                        } else {
                            pendingSaveResult = result
                            pendingSaveContent = call.argument<String>("content")
                            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "application/json"
                                putExtra(Intent.EXTRA_TITLE, call.argument<String>("fileName") ?: "todo_list_backup.json")
                            }
                            startActivityForResult(intent, SAVE_JSON_REQUEST)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // 电池优化白名单（小米等 ROM 后台拦截提醒时需要；flutter_local_notifications 18.x 无此 API）
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "todo_list/battery_optimization")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoring" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(POWER_SERVICE) as PowerManager
                            result.success(pm.isIgnoringBatteryOptimizations(packageName))
                        } else {
                            result.success(true)
                        }
                    }
                    "requestIgnore" -> {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                    data = Uri.parse("package:$packageName")
                                }
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            // 部分 ROM 不支持该 Intent，fallback 到白名单列表页
                            try {
                                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                                result.success(true)
                            } catch (e2: Exception) {
                                result.success(false)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "todo_list/widgets")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "refresh" -> {
                        TaskWidgetProvider.updateAll(this)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Android API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val uri: Uri? = if (resultCode == Activity.RESULT_OK) data?.data else null
        when (requestCode) {
            OPEN_JSON_REQUEST -> {
                val result = pendingOpenResult
                pendingOpenResult = null
                if (uri == null) {
                    result?.success(null)
                    return
                }
                try {
                    val content = contentResolver.openInputStream(uri)
                        ?.bufferedReader(Charsets.UTF_8)
                        ?.use { it.readText() }
                    result?.success(content)
                } catch (error: Exception) {
                    result?.error("read_failed", error.message, null)
                }
            }
            SAVE_JSON_REQUEST -> {
                val result = pendingSaveResult
                val content = pendingSaveContent
                pendingSaveResult = null
                pendingSaveContent = null
                if (uri == null || content == null) {
                    result?.success(false)
                    return
                }
                try {
                    contentResolver.openOutputStream(uri)
                        ?.bufferedWriter(Charsets.UTF_8)
                        ?.use { it.write(content) }
                    result?.success(true)
                } catch (error: Exception) {
                    result?.error("write_failed", error.message, null)
                }
            }
        }
    }
}
