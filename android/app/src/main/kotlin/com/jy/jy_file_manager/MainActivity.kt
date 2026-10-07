package com.jy.jy_file_manager

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var shizukuBridge: ShizukuBridge? = null
    private var appBridge: AppBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Root 通道由 Dart 侧直接调用 su 实现，无需原生桥。
        // Shizuku 的 binder API 只能在原生侧使用，故注册桥接。
        shizukuBridge = ShizukuBridge(this)
            .also { it.attach(flutterEngine.dartExecutor.binaryMessenger) }

        // 应用/安装包信息（PackageManager）也只能在原生侧访问
        appBridge = AppBridge(this)
            .also { it.attach(flutterEngine.dartExecutor.binaryMessenger) }
    }

    override fun onDestroy() {
        shizukuBridge?.detach()
        shizukuBridge = null
        appBridge?.detach()
        appBridge = null
        super.onDestroy()
    }
}
