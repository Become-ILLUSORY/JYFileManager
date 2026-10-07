package com.jy.jy_file_manager

import android.app.Activity
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * 应用/安装包信息桥。
 *
 * 提供 Flutter 侧无法直接拿到的能力：
 *   - 已安装应用列表（PackageManager）
 *   - 应用图标（Drawable → PNG 字节）
 *   - APK 图标（从 APK 文件里取图标）
 *   - 启动应用 / 打开应用详情 / 卸载
 *   - 安装拆分 APK（多 APK 一起装）
 *
 * 这些都必须走系统 API，纯 Dart 做不到，因此单独建桥。
 */
class AppBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private val pm: PackageManager get() = activity.packageManager

    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getInstalledApps" -> {
                    val includeSystem = call.argument<Boolean>("includeSystem") ?: false
                    result.success(getInstalledApps(includeSystem))
                }
                "getAppIcon" -> {
                    val pkg = call.argument<String>("packageName")
                    result.success(if (pkg == null) null else getAppIcon(pkg))
                }
                "getApkIcon" -> {
                    val path = call.argument<String>("apkPath")
                    result.success(if (path == null) null else getApkIcon(path))
                }
                "getApkInfo" -> {
                    val path = call.argument<String>("apkPath")
                    result.success(if (path == null) null else getApkInfo(path))
                }
                "launchApp" -> {
                    val pkg = call.argument<String>("packageName")
                    result.success(pkg != null && launchApp(pkg))
                }
                "openAppDetails" -> {
                    val pkg = call.argument<String>("packageName")
                    result.success(pkg != null && openAppDetails(pkg))
                }
                "uninstallApp" -> {
                    val pkg = call.argument<String>("packageName")
                    result.success(pkg != null && uninstallApp(pkg))
                }
                "installSplitApks" -> {
                    val paths = call.argument<List<String>>("paths")
                    result.success(paths != null && installSplitApks(paths))
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("app_bridge_error", e.message, null)
        }
    }

    // ---------- 已安装应用 ----------

    private fun getInstalledApps(includeSystem: Boolean): List<Map<String, Any?>> {
        val flags = PackageManager.GET_META_DATA
        val packages = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getInstalledPackages(PackageManager.PackageInfoFlags.of(flags.toLong()))
        } else {
            @Suppress("DEPRECATION")
            pm.getInstalledPackages(flags)
        }

        val out = ArrayList<Map<String, Any?>>()
        for (pi in packages) {
            val ai = pi.applicationInfo ?: continue
            val isSystem = (ai.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            if (isSystem && !includeSystem) continue

            val label = runCatching { pm.getApplicationLabel(ai).toString() }.getOrDefault(pi.packageName)
            val apkSize = runCatching {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    pi.applicationInfo?.let {
                        val f = java.io.File(it.sourceDir)
                        f.length()
                    } ?: 0L
                } else 0L
            }.getOrDefault(0L)

            val splits = runCatching {
                // splitSourceDirs 挂在 applicationInfo 上（API 21+）
                val dirs = ai.splitSourceDirs
                if (dirs == null) emptyList<String>() else dirs.toList()
            }.getOrDefault(emptyList())

            out.add(
                mapOf(
                    "name" to label,
                    "packageName" to pi.packageName,
                    "version" to (pi.versionName ?: ""),
                    "apkSize" to apkSize.toInt(),
                    "isSystem" to isSystem,
                    "installTime" to pi.firstInstallTime,
                    "sourceDir" to (ai.sourceDir ?: ""),
                    "splitSourceDirs" to splits,
                )
            )
        }
        out.sortBy { (it["name"] as? String)?.lowercase() ?: "" }
        return out
    }

    // ---------- 图标 ----------

    private fun drawableToPng(drawable: Drawable, size: Int = 192): ByteArray? {
        return runCatching {
            val bmp = if (drawable is BitmapDrawable && drawable.bitmap != null) {
                drawable.bitmap
            } else {
                val w = if (drawable.intrinsicWidth > 0) drawable.intrinsicWidth else size
                val h = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else size
                Bitmap.createBitmap(w.coerceAtMost(size * 2), h.coerceAtMost(size * 2), Bitmap.Config.ARGB_8888).also {
                    val c = android.graphics.Canvas(it)
                    drawable.setBounds(0, 0, it.width, it.height)
                    drawable.draw(c)
                }
            }
            val stream = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.PNG, 100, stream)
            stream.toByteArray()
        }.getOrNull()
    }

    private fun getAppIcon(packageName: String): ByteArray? {
        return runCatching {
            val ai = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getApplicationInfo(packageName, PackageManager.ApplicationInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.getApplicationInfo(packageName, 0)
            }
            drawableToPng(pm.getApplicationIcon(ai))
        }.getOrNull()
    }

    private fun getApkIcon(apkPath: String): ByteArray? {
        return runCatching {
            val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getPackageArchiveInfo(apkPath, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageArchiveInfo(apkPath, 0)
            }
            val ai = info?.applicationInfo ?: return null
            // 必须设置这两个路径，否则取不到图标资源
            ai.sourceDir = apkPath
            ai.publicSourceDir = apkPath
            drawableToPng(ai.loadIcon(pm))
        }.getOrNull()
    }

    private fun getApkInfo(apkPath: String): Map<String, Any?>? {
        return runCatching {
            val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getPackageArchiveInfo(apkPath, PackageManager.PackageInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageArchiveInfo(apkPath, 0)
            } ?: return null
            val ai = info.applicationInfo
            ai?.sourceDir = apkPath
            ai?.publicSourceDir = apkPath
            val label = runCatching { pm.getApplicationLabel(ai!!).toString() }.getOrDefault("")
            mapOf(
                "label" to label,
                "packageName" to info.packageName,
                "version" to (info.versionName ?: ""),
                "versionCode" to (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                    info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong()),
                "isSystem" to ((ai?.flags ?: 0) and ApplicationInfo.FLAG_SYSTEM != 0),
            )
        }.getOrNull()
    }

    // ---------- 操作 ----------

    private fun launchApp(packageName: String): Boolean {
        return runCatching {
            val intent = pm.getLaunchIntentForPackage(packageName) ?: return false
            intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
            true
        }.getOrDefault(false)
    }

    private fun openAppDetails(packageName: String): Boolean {
        return runCatching {
            val intent = android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = android.net.Uri.parse("package:$packageName")
                addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(intent)
            true
        }.getOrDefault(false)
    }

    private fun uninstallApp(packageName: String): Boolean {
        return runCatching {
            val intent = android.content.Intent(android.content.Intent.ACTION_DELETE).apply {
                data = android.net.Uri.parse("package:$packageName")
                addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(intent)
            true
        }.getOrDefault(false)
    }

    /** 多 APK（拆分包）一起安装：交给系统安装器逐个处理 */
    private fun installSplitApks(paths: List<String>): Boolean {
        return runCatching {
            if (paths.isEmpty()) return false
            // 系统安装器一次只能装一个 APK；拆分包依次触发安装流程。
            // 这里只启动第一个，其余由调用方在装完后继续。
            val first = java.io.File(paths[0])
            if (!first.exists()) return false
            val intent = android.content.Intent(android.content.Intent.ACTION_VIEW).apply {
                setDataAndType(
                    android.net.Uri.fromFile(first),
                    "application/vnd.android.package-archive"
                )
                addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivity(intent)
            true
        }.getOrDefault(false)
    }

    companion object {
        const val CHANNEL = "jyfilemanager/app"
    }
}
