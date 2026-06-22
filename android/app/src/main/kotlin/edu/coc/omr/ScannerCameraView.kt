package edu.coc.omr

import android.content.Context
import android.util.Log
import android.view.View
import io.flutter.plugin.platform.PlatformView

class ScannerCameraView(
    context: Context,
    private val viewId: Int,
    creationParams: Map<String, Any>?,
) : PlatformView {
    companion object {
        private const val TAG = "ScannerCamera"
    }

    private val previewView = androidx.camera.view.PreviewView(context)
    private val session = ScannerCameraSession(context, previewView)

    init {
        ScannerCameraRegistry.put(viewId, session)

        val width = (creationParams?.get("width") as? Number)?.toInt() ?: 0
        val height = (creationParams?.get("height") as? Number)?.toInt() ?: 0
        if (width > 0 && height > 0) {
            session.bind(
                viewWidth = width,
                viewHeight = height,
                onReady = { aspect ->
                    Log.i(TAG, "View $viewId auto-bound aspect=$aspect")
                },
                onError = { message ->
                    Log.e(TAG, "View $viewId auto-bind failed: $message")
                },
            )
        }
    }

    override fun getView(): View = previewView

    override fun dispose() {
        ScannerCameraRegistry.remove(viewId)
    }
}
