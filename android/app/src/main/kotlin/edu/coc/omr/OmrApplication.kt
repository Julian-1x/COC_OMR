package edu.coc.omr

import android.app.Application
import android.util.Log

/** Preloads scan tier + OpenCV before Flutter so exam day is ready at unlock. */
class OmrApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        // Synchronous and cheap — ActivityManager only. Camera/OpenCV read the cache later.
        val tier = DeviceScanTier.warm(this)
        Log.i(
            "DeviceScanTier",
            "Resolved at launch: $tier " +
                "heapClassMb=${DeviceScanTier.cachedHeapClassMb()} " +
                "capture=${tier.captureSize.width}x${tier.captureSize.height} " +
                "decodeMax=${tier.decodeMaxDimension} " +
                "remainingHeapMb=${DeviceScanTier.remainingHeapMb()}",
        )

        Thread(
            {
                try {
                    val loaded = OpenCvRuntime.tryLoad()
                    Log.i("OpenCV", "Application preload: loaded=$loaded")
                } catch (e: Throwable) {
                    Log.e("OpenCV", "Application preload failed", e)
                }
            },
            "opencv-preload",
        ).start()
    }
}
