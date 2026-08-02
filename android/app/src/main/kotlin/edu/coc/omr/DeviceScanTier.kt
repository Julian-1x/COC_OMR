package edu.coc.omr

import android.app.ActivityManager
import android.content.Context
import android.util.Size
import androidx.camera.core.resolutionselector.ResolutionStrategy

/**
 * Exam-day performance tiers from **what this process can use**, not phone price/brand.
 *
 * Primary signal: [ActivityManager.getLargeMemoryClass] (app has android:largeHeap).
 * Forced LOW when [ActivityManager.isLowRamDevice].
 *
 * Thresholds (heap class MB):
 * - LOW: ≤192 (or low-RAM flag)
 * - MID: ≤256
 * - HIGH: ≤384
 * - VERY_HIGH: >384
 */
enum class DeviceScanTier {
    LOW,
    MID,
    HIGH,
    VERY_HIGH,
    ;

    val captureSize: Size
        get() = when (this) {
            LOW -> Size(1280, 960)
            MID -> Size(1600, 1200)
            HIGH -> Size(1920, 1440)
            VERY_HIGH -> Size(2560, 1920)
        }

    val previewSize: Size
        get() = when (this) {
            LOW -> Size(960, 720)
            MID -> Size(1280, 960)
            HIGH, VERY_HIGH -> Size(1920, 1440)
        }

    val jpegQuality: Int
        get() = when (this) {
            LOW -> 82
            MID -> 88
            HIGH -> 92
            VERY_HIGH -> 95
        }

    /** Longest edge when decoding for OpenCV (warp target is only ~595×842). */
    val decodeMaxDimension: Int
        get() = when (this) {
            LOW -> 1600
            MID -> 1800
            HIGH -> 2000
            VERY_HIGH -> 2400
        }

    /** Dart-side pre-compress longest edge (before native). */
    val dartOptimizeMaxDimension: Int
        get() = when (this) {
            LOW -> 1600
            MID -> 1800
            HIGH -> 2000
            VERY_HIGH -> 2400
        }

    val dartJpegQuality: Int
        get() = when (this) {
            LOW -> 82
            MID -> 88
            HIGH, VERY_HIGH -> 90
        }

    /** Prefer lower sensor modes on weak devices so CameraX never jumps to 12MP. */
    val captureFallbackRule: Int
        get() = when (this) {
            LOW, MID -> ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER
            HIGH, VERY_HIGH -> ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER
        }

    val isConstrained: Boolean
        get() = this == LOW || this == MID

    companion object {
        @Volatile
        private var cached: DeviceScanTier? = null

        @Volatile
        private var cachedHeapClassMb: Int = -1

        /** Last resolved tier (null until [warm] / [resolve]). */
        fun cachedOrNull(): DeviceScanTier? = cached

        fun cachedHeapClassMb(): Int = cachedHeapClassMb

        /**
         * Resolve once at process start. Cheap (ActivityManager only) — call from
         * [Application.onCreate] so capture/decode limits are known before the scanner opens.
         */
        fun warm(context: Context): DeviceScanTier {
            cached?.let { return it }
            return resolve(context)
        }

        fun resolve(context: Context): DeviceScanTier {
            cached?.let { return it }

            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                ?: return MID.also { cached = it }

            if (am.isLowRamDevice) {
                cachedHeapClassMb = am.memoryClass
                return LOW.also { cached = it }
            }

            // largeHeap=true in the manifest — use largeMemoryClass when available.
            val heapMb = try {
                maxOf(am.memoryClass, am.largeMemoryClass)
            } catch (_: Throwable) {
                am.memoryClass
            }

            cachedHeapClassMb = heapMb
            return fromHeapClassMb(heapMb).also { cached = it }
        }

        fun fromHeapClassMb(heapMb: Int): DeviceScanTier {
            return when {
                heapMb <= 192 -> LOW
                heapMb <= 256 -> MID
                heapMb <= 384 -> HIGH
                else -> VERY_HIGH
            }
        }

        /** Runtime remaining capacity until [Runtime.maxMemory] (MB). */
        fun remainingHeapMb(): Long {
            val runtime = Runtime.getRuntime()
            val used = runtime.totalMemory() - runtime.freeMemory()
            return (runtime.maxMemory() - used) / (1024 * 1024)
        }

        /**
         * May drop one tier for this scan if remaining heap is tight
         * (e.g. HIGH device under pressure → behave like MID for decode).
         */
        fun forProcessing(base: DeviceScanTier): DeviceScanTier {
            val remaining = remainingHeapMb()
            return when {
                remaining < 48 && base > LOW -> LOW
                remaining < 80 && base > MID -> MID
                remaining < 120 && base == VERY_HIGH -> HIGH
                else -> base
            }
        }
    }
}
