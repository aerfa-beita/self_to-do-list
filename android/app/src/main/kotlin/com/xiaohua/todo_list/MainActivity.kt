package com.xiaohua.todo_list

import android.app.Activity
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "stride/full_screen_intent")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canUse" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            val manager = getSystemService(NotificationManager::class.java)
                            result.success(manager.canUseFullScreenIntent())
                        } else {
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "todo_list/app_update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInstalledVersion" -> {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        result.success(
                            mapOf(
                                "versionName" to (info.versionName ?: ""),
                                "versionCode" to versionCode(info),
                            )
                        )
                    }
                    "getUpdateCachePath" -> {
                        val updateDir = File(cacheDir, "updates").apply { mkdirs() }
                        result.success(File(updateDir, "app-update.apk").absolutePath)
                    }
                    "verifyApk" -> {
                        val path = call.argument<String>("path")
                        val expectedCode = call.argument<Number>("versionCode")?.toLong()
                        val expectedName = call.argument<String>("versionName")
                        Thread {
                            val verification = verifyApk(path, expectedCode, expectedName)
                            runOnUiThread { result.success(verification) }
                        }.start()
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        result.success(installApk(path))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun verifyApk(
        path: String?,
        expectedVersionCode: Long?,
        expectedVersionName: String?,
    ): Map<String, Any> {
        try {
            val apk = trustedUpdateFile(path)
                ?: return mapOf("valid" to false, "reason" to "安装包路径无效")
            if (!apk.isFile || apk.length() <= 0L) {
                return mapOf("valid" to false, "reason" to "安装包不存在")
            }
            val archive = packageInfoForArchive(apk)
                ?: return mapOf("valid" to false, "reason" to "无法读取安装包信息")
            if (archive.packageName != packageName) {
                return mapOf("valid" to false, "reason" to "安装包应用标识不匹配")
            }
            if (expectedVersionCode == null || versionCode(archive) != expectedVersionCode) {
                return mapOf("valid" to false, "reason" to "安装包版本号与清单不匹配")
            }
            if (expectedVersionName.isNullOrBlank() || archive.versionName != expectedVersionName) {
                return mapOf("valid" to false, "reason" to "安装包版本名称与清单不匹配")
            }
            val installed = packageInfoWithSigners(packageName)
            val installedSigners = signerDigests(installed)
            val archiveSigners = signerDigests(archive)
            if (installedSigners.isEmpty() ||
                archiveSigners.isEmpty() ||
                installedSigners != archiveSigners
            ) {
                return mapOf("valid" to false, "reason" to "安装包签名与当前应用不一致")
            }
            return mapOf("valid" to true)
        } catch (error: Exception) {
            return mapOf("valid" to false, "reason" to (error.message ?: "安装包校验失败"))
        }
    }

    private fun installApk(path: String?): String {
        return try {
            val apk = trustedUpdateFile(path) ?: return "unsupported"
            if (!apk.isFile) return "unsupported"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !packageManager.canRequestPackageInstalls()
            ) {
                startActivity(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                        data = Uri.parse("package:$packageName")
                    }
                )
                return "permission_required"
            }
            val contentUri = FileProvider.getUriForFile(
                this,
                "$packageName.update-files",
                apk,
            )
            startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(contentUri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            )
            "started"
        } catch (_: Exception) {
            "unsupported"
        }
    }

    private fun trustedUpdateFile(path: String?): File? {
        if (path.isNullOrBlank()) return null
        val updateDir = File(cacheDir, "updates").canonicalFile
        val candidate = File(path).canonicalFile
        if (candidate.parentFile != updateDir) return null
        return candidate
    }

    private fun packageInfoForArchive(apk: File): PackageInfo? {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }
        @Suppress("DEPRECATION")
        return packageManager.getPackageArchiveInfo(apk.absolutePath, flags)
    }

    private fun packageInfoWithSigners(packageId: String): PackageInfo {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }
        @Suppress("DEPRECATION")
        return packageManager.getPackageInfo(packageId, flags)
    }

    private fun signerDigests(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = info.signingInfo ?: return emptySet()
            signingInfo.apkContentsSigners
        } else {
            @Suppress("DEPRECATION")
            info.signatures
        }
        return signatures?.map { signature ->
            MessageDigest.getInstance("SHA-256")
                .digest(signature.toByteArray())
                .joinToString("") { byte -> "%02x".format(byte) }
        }?.toSet() ?: emptySet()
    }

    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
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
