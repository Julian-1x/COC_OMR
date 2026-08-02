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
        // Binding is driven by Flutter via bindView — avoid double-bind races on cold start.
    }

    override fun getView(): View = previewView

    override fun dispose() {
        ScannerCameraRegistry.remove(viewId)
    }
}
