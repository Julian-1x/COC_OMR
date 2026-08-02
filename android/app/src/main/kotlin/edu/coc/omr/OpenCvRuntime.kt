package edu.coc.omr

import android.util.Log
import org.opencv.android.OpenCVLoader

/** Loads OpenCV once, as early as possible, shared by Application and MainActivity. */
object OpenCvRuntime {
    private const val TAG = "OpenCV"
    private val loadLock = Any()

    @Volatile
    var isInitialized: Boolean = false
        private set

    @Volatile
    var lastError: String? = null
        private set

    /** Thread-safe; safe to call from Application preloader or scan engine. */
    fun tryLoad(): Boolean {
        if (isInitialized) {
            return true
        }
        synchronized(loadLock) {
            if (isInitialized) {
                return true
            }
            try {
                // OpenCV's libopencv_java4.so depends on the NDK C++ runtime.
                try {
                    System.loadLibrary("c++_shared")
                } catch (_: UnsatisfiedLinkError) {
                    // Already loaded by another native dependency — OK.
                }
                val ok = OpenCVLoader.initLocal()
                isInitialized = ok
                if (ok) {
                    lastError = null
                    Log.i(TAG, "OpenCV loaded")
                } else {
                    lastError = "OpenCVLoader.initLocal() returned false"
                    Log.e(TAG, lastError!!)
                }
            } catch (e: UnsatisfiedLinkError) {
                isInitialized = false
                lastError = "UnsatisfiedLinkError: ${e.message}"
                Log.e(TAG, lastError, e)
            } catch (e: Exception) {
                isInitialized = false
                lastError = "${e.javaClass.simpleName}: ${e.message}"
                Log.e(TAG, lastError, e)
            }
            return isInitialized
        }
    }
}
