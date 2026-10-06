package com.jy.jy_file_manager

import android.app.Activity
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import moe.shizuku.server.IShizukuService
import rikka.shizuku.Shizuku
import java.util.concurrent.Executors

/**
 * Shizuku 桥接：为没有 Root、但愿意通过 adb 授权（Shizuku）的用户提供特权操作。
 *
 * 本应用不实现任何提权手段，只作为客户端向用户已安装的 Shizuku 申请授权；
 * 授权与否由用户在 Shizuku 应用内决定，可随时撤销。
 *
 * 特权命令统一通过 IShizukuService.newProcess 执行，与 `su -c` 语义一致。
 */
class ShizukuBridge(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "jyfilemanager/privilege"

        /** 授权请求码，回调时用于匹配 */
        private const val REQ_CODE = 0x4A59

        /** Shizuku 管理器包名 */
        private const val SHIZUKU_PKG = "moe.shizuku.manager"
    }

    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var channel: MethodChannel? = null

    /** 等待授权结果的调用方 */
    private var pendingRequest: MethodChannel.Result? = null

    /** 授权结果超时保护 */
    private val requestTimeout = Runnable {
        pendingRequest?.let {
            pendingRequest = null
            it.success(statusMap())
        }
    }

    private val permissionListener =
        Shizuku.OnRequestPermissionResultListener { code, _ ->
            if (code == REQ_CODE) {
                main.removeCallbacks(requestTimeout)
                val pending = pendingRequest
                pendingRequest = null
                main.post { pending?.success(statusMap()) }
            }
        }

    private val binderReceivedListener = Shizuku.OnBinderReceivedListener {
        main.post { channel?.invokeMethod("binderReceived", statusMap()) }
    }

    private val binderDeadListener = Shizuku.OnBinderDeadListener {
        main.post { channel?.invokeMethod("binderDead", statusMap()) }
    }

    /** 注册通道与 Shizuku 监听 */
    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        runCatching {
            Shizuku.addRequestPermissionResultListener(permissionListener)
            Shizuku.addBinderReceivedListenerSticky(binderReceivedListener)
            Shizuku.addBinderDeadListener(binderDeadListener)
        }
    }

    /** 注销监听，避免 Activity 销毁后泄漏 */
    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        runCatching {
            Shizuku.removeRequestPermissionResultListener(permissionListener)
            Shizuku.removeBinderReceivedListener(binderReceivedListener)
            Shizuku.removeBinderDeadListener(binderDeadListener)
        }
        main.removeCallbacks(requestTimeout)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(statusMap())

            "request" -> requestPermission(result)

            "exec" -> {
                val command = call.argument<String>("command").orEmpty()
                if (command.isEmpty()) {
                    result.success(mapOf("ok" to false, "error" to "empty_command"))
                    return
                }
                // binder 调用与管道读取都会阻塞，放到后台线程
                worker.execute {
                    val payload = execCommand(command)
                    main.post { result.success(payload) }
                }
            }

            else -> result.notImplemented()
        }
    }

    /** 申请授权；结果通过监听器异步返回 */
    private fun requestPermission(result: MethodChannel.Result) {
        if (!isBinderAlive()) {
            result.success(statusMap())
            return
        }
        if (isGranted()) {
            result.success(statusMap())
            return
        }
        pendingRequest = result
        main.postDelayed(requestTimeout, 60_000)
        runCatching { Shizuku.requestPermission(REQ_CODE) }
            .onFailure {
                main.removeCallbacks(requestTimeout)
                pendingRequest = null
                result.success(statusMap())
            }
    }

    /** 以 shell（uid 2000）身份执行命令 */
    private fun execCommand(command: String): Map<String, Any?> {
        if (!isBinderAlive()) {
            return mapOf("ok" to false, "error" to "binder_not_running")
        }
        if (!isGranted()) {
            return mapOf("ok" to false, "error" to "permission_denied")
        }
        return try {
            val service = IShizukuService.Stub.asInterface(Shizuku.getBinder())
            val process = service.newProcess(arrayOf("sh", "-c", command), null, null)
            val stdout = ParcelFileDescriptor.AutoCloseInputStream(process.inputStream)
                .use { it.readBytes() }
            val stderr = ParcelFileDescriptor.AutoCloseInputStream(process.errorStream)
                .use { it.readBytes() }
            val code = process.waitFor()
            mapOf(
                "ok" to true,
                "code" to code,
                "stdout" to String(stdout, Charsets.UTF_8),
                "stderr" to String(stderr, Charsets.UTF_8),
            )
        } catch (t: Throwable) {
            mapOf("ok" to false, "error" to (t.message ?: t.javaClass.simpleName))
        }
    }

    private fun isBinderAlive(): Boolean = runCatching { Shizuku.pingBinder() }.getOrDefault(false)

    private fun isGranted(): Boolean = runCatching {
        val version = Shizuku.getVersion()
        val granted = if (version >= 11) {
            Shizuku.checkSelfPermission()
        } else {
            Shizuku.checkRemotePermission(activity.packageName)
        }
        granted == PackageManager.PERMISSION_GRANTED
    }.getOrDefault(false)

    private fun isShizukuInstalled(): Boolean = runCatching {
        activity.packageManager.getPackageInfo(SHIZUKU_PKG, 0)
        true
    }.getOrDefault(false)

    /** 当前 Shizuku 状态快照 */
    private fun statusMap(): Map<String, Any?> {
        if (!isBinderAlive()) {
            return mapOf(
                "available" to false,
                "granted" to false,
                "installed" to isShizukuInstalled(),
                "reason" to "binder_not_running",
            )
        }
        val version = runCatching { Shizuku.getVersion() }.getOrDefault(-1)
        val uid = runCatching { Shizuku.getUid() }.getOrDefault(-1)
        return mapOf(
            "available" to true,
            "granted" to isGranted(),
            "installed" to true,
            "version" to version,
            "uid" to uid,
            "reason" to if (isGranted()) "granted" else "not_granted",
        )
    }
}
