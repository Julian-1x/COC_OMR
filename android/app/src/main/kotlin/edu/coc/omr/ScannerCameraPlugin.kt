package edu.coc.omr

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object ScannerCameraPlugin {
    const val CHANNEL = "edu.coc.omr/scanner_camera"
    const val VIEW_TYPE = "edu.coc.omr/scanner_camera"

    var hostActivity: FlutterActivity? = null
        private set

    fun register(flutterEngine: FlutterEngine, activity: FlutterActivity) {
        hostActivity = activity

        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(VIEW_TYPE, ScannerCameraViewFactory())

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPreviewAspect" -> {
                        result.success(9.0 / 16.0)
                    }

                    "bindView" -> {
                        val viewId = call.argument<Int>("viewId")
                        val width = call.argument<Int>("width") ?: 0
                        val height = call.argument<Int>("height") ?: 0
                        if (viewId == null) {
                            result.error("INVALID_ARGS", "viewId required", null)
                            return@setMethodCallHandler
                        }

                        val session = ScannerCameraRegistry.get(viewId)
                        if (session == null) {
                            result.error("NO_SESSION", "Camera view not found", null)
                            return@setMethodCallHandler
                        }

                        session.bind(
                            viewWidth = width,
                            viewHeight = height,
                            onReady = { aspect -> result.success(aspect) },
                            onError = { message -> result.error("BIND_FAILED", message, null) },
                        )
                    }

                    "configureForScanning" -> {
                        val viewId = call.argument<Int>("viewId")
                        val session = viewId?.let { ScannerCameraRegistry.get(it) }
                        if (session == null) {
                            result.error("NO_SESSION", "Camera view not found", null)
                            return@setMethodCallHandler
                        }
                        session.configureForScanning()
                        result.success(null)
                    }

                    "setFocusPoint" -> {
                        val viewId = call.argument<Int>("viewId")
                        val x = call.argument<Double>("x")?.toFloat()
                        val y = call.argument<Double>("y")?.toFloat()
                        val session = viewId?.let { ScannerCameraRegistry.get(it) }
                        if (session == null || x == null || y == null) {
                            result.error("INVALID_ARGS", "viewId, x, y required", null)
                            return@setMethodCallHandler
                        }
                        session.setFocusPoint(x, y)
                        result.success(null)
                    }

                    "capture" -> {
                        val viewId = call.argument<Int>("viewId")
                        val session = viewId?.let { ScannerCameraRegistry.get(it) }
                        if (session == null) {
                            result.error("NO_SESSION", "Camera view not found", null)
                            return@setMethodCallHandler
                        }
                        session.capture(result)
                    }

                    "disposeView" -> {
                        val viewId = call.argument<Int>("viewId")
                        if (viewId != null) {
                            ScannerCameraRegistry.remove(viewId)
                        }
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
