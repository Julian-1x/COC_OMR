package edu.coc.omr

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity: FlutterActivity() {
    private val CHANNEL = "opencv"
    private val TAG = "OpenCV"
    @Volatile
    private var openCvInitialized = false
    private val omrProcessor by lazy { OmrProcessor(applicationContext) }
    private val processingScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private val openCvInitMutex = Mutex()
    @Volatile
    private var openCvInitJob: Job? = null

    // Concurrent processing limits for low-end devices
    private val isProcessing = AtomicBoolean(false)
    private val MAX_OPENCV_LOAD_ATTEMPTS = 8
    private val MAX_IMAGE_SIZE_BYTES = 12 * 1024 * 1024  // keep aligned with OmrProcessor
    private val MIN_FREE_MEMORY_MB = 50
    private val NATIVE_PROCESS_TIMEOUT_MS = 20_000L
    private val OPEN_CV_READY_WAIT_MS = 45_000L

    private fun syncOpenCvFlag(): Boolean {
        if (OpenCvRuntime.isInitialized) {
            openCvInitialized = true
        }
        return openCvInitialized || OpenCvRuntime.isInitialized
    }

    private fun kickOffOpenCvInit(forceRestart: Boolean = false) {
        synchronized(this) {
            if (!forceRestart && (syncOpenCvFlag() || openCvInitJob?.isActive == true)) {
                return
            }
            if (forceRestart) {
                openCvInitJob?.cancel()
                openCvInitJob = null
                openCvInitialized = false
            }
            openCvInitJob = processingScope.launch {
                ensureOpenCvLoaded(forceRestart = forceRestart)
            }
        }
    }

    /** Thread-safe OpenCV load — one load at a time; callers await the same job. */
    private suspend fun ensureOpenCvLoaded(forceRestart: Boolean = false): Boolean {
        if (!forceRestart && syncOpenCvFlag()) {
            return true
        }

        return openCvInitMutex.withLock {
            if (!forceRestart && syncOpenCvFlag()) {
                return@withLock true
            }

            if (forceRestart) {
                openCvInitialized = false
            }

            var attempt = 0
            while (!syncOpenCvFlag() && attempt < MAX_OPENCV_LOAD_ATTEMPTS) {
                attempt++
                if (attempt == 1) {
                    delay(300)
                }

                val loaded = withContext(Dispatchers.IO) {
                    OpenCvRuntime.tryLoad()
                }

                if (loaded) {
                    Log.i(TAG, "OpenCV loaded successfully (attempt $attempt)")
                    openCvInitialized = true
                    break
                }

                Log.e(
                    TAG,
                    "OpenCV load failed (attempt $attempt/$MAX_OPENCV_LOAD_ATTEMPTS): ${OpenCvRuntime.lastError}",
                )
                if (attempt < MAX_OPENCV_LOAD_ATTEMPTS) {
                    delay((400L * attempt).coerceAtMost(2500L))
                }
            }

            if (!syncOpenCvFlag()) {
                Log.e(
                    TAG,
                    "OpenCV failed to load after $MAX_OPENCV_LOAD_ATTEMPTS attempts: ${OpenCvRuntime.lastError}",
                )
            }
            syncOpenCvFlag()
        }
    }

    /** Wait for any in-flight init, starting one if needed. Never aborts a running load. */
    private suspend fun awaitOpenCvReady(forceRestart: Boolean = false): Boolean {
        if (!forceRestart && syncOpenCvFlag()) {
            return true
        }

        if (!forceRestart) {
            val activeJob = synchronized(this) { openCvInitJob?.takeIf { it.isActive } }
            if (activeJob != null) {
                withTimeoutOrNull(OPEN_CV_READY_WAIT_MS) {
                    activeJob.join()
                }
                if (syncOpenCvFlag()) {
                    return true
                }
            }
        }

        kickOffOpenCvInit(forceRestart = forceRestart)
        val job = synchronized(this) { openCvInitJob }
        if (job != null) {
            withTimeoutOrNull(OPEN_CV_READY_WAIT_MS) {
                job.join()
            }
        }
        if (syncOpenCvFlag()) {
            return true
        }

        return ensureOpenCvLoaded(forceRestart = forceRestart)
    }

    private fun checkMemoryAvailable(): Boolean {
        val before = DeviceScanTier.remainingHeapMb()
        val runtime = Runtime.getRuntime()
        val freeInHeap = runtime.freeMemory() / (1024 * 1024)
        val maxMb = runtime.maxMemory() / (1024 * 1024)
        Log.d(TAG, "Memory: remaining=${before}MB freeInHeap=${freeInHeap}MB max=${maxMb}MB")

        // Prefer remaining capacity to max heap — Runtime.freeMemory() alone is often tiny
        // even when the heap can still grow.
        if (before >= MIN_FREE_MEMORY_MB) {
            return true
        }
        System.gc()
        val after = DeviceScanTier.remainingHeapMb()
        Log.d(TAG, "After GC: remaining=${after}MB")
        // Allow processing when at least ~32MB can still be allocated for decode+mats.
        return after >= 32
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        syncOpenCvFlag()
        kickOffOpenCvInit()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        ScannerCameraPlugin.register(flutterEngine, this)
        kickOffOpenCvInit()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "process" -> {
                        processingScope.launch {
                            try {
                                val ready = awaitOpenCvReady()
                                if (!ready) {
                                    withContext(Dispatchers.Main) {
                                        result.error(
                                            "OPENCV_NOT_READY",
                                            "OpenCV failed to initialize",
                                            mapOf("initFailed" to true),
                                        )
                                    }
                                    return@launch
                                }

                                if (!isProcessing.compareAndSet(false, true)) {
                                    withContext(Dispatchers.Main) {
                                        result.error(
                                            "BUSY",
                                            "Already processing an image. Please wait.",
                                            null,
                                        )
                                    }
                                    return@launch
                                }

                                val bytes = call.arguments as? ByteArray
                                if (bytes == null || bytes.isEmpty()) {
                                    isProcessing.set(false)
                                    withContext(Dispatchers.Main) {
                                        result.error("INVALID_INPUT", "No image data provided", null)
                                    }
                                    return@launch
                                }

                                if (bytes.size > MAX_IMAGE_SIZE_BYTES) {
                                    isProcessing.set(false)
                                    withContext(Dispatchers.Main) {
                                        result.error(
                                            "IMAGE_TOO_LARGE",
                                            "Image size ${bytes.size / 1024 / 1024}MB exceeds maximum ${MAX_IMAGE_SIZE_BYTES / 1024 / 1024}MB",
                                            null,
                                        )
                                    }
                                    return@launch
                                }

                                if (!checkMemoryAvailable()) {
                                    isProcessing.set(false)
                                    withContext(Dispatchers.Main) {
                                        result.error(
                                            "LOW_MEMORY",
                                            "Device memory too low. Please close other apps and try again.",
                                            null,
                                        )
                                    }
                                    return@launch
                                }

                                try {
                                    val processingResult = withTimeout(NATIVE_PROCESS_TIMEOUT_MS) {
                                        omrProcessor.processImage(bytes)
                                    }
                                    val jsonResult = processingResult.toJson().toString()
                                    withContext(Dispatchers.Main) {
                                        result.success(jsonResult)
                                    }
                                } catch (e: TimeoutCancellationException) {
                                    Log.e(TAG, "process timed out after ${NATIVE_PROCESS_TIMEOUT_MS}ms")
                                    withContext(Dispatchers.Main) {
                                        result.error(
                                            "PROCESS_TIMEOUT",
                                            "Scan processing timed out",
                                            null,
                                        )
                                    }
                                } catch (e: OutOfMemoryError) {
                                    Log.e(TAG, "Out of memory: ${e.message}", e)
                                    System.gc()
                                    withContext(Dispatchers.Main) {
                                        result.error(
                                            "OUT_OF_MEMORY",
                                            "Device ran out of memory. Please close other apps.",
                                            null,
                                        )
                                    }
                                } catch (e: Exception) {
                                    Log.e(TAG, "Processing error: ${e.message}", e)
                                    withContext(Dispatchers.Main) {
                                        result.error("PROCESS_ERROR", e.message, e.stackTraceToString())
                                    }
                                } finally {
                                    isProcessing.set(false)
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "process handler error: ${e.message}", e)
                                isProcessing.set(false)
                                withContext(Dispatchers.Main) {
                                    result.error("PROCESS_ERROR", e.message, null)
                                }
                            }
                        }
                    }

                    "processWithConfig" -> {
                        processingScope.launch {
                            try {
                                val ready = awaitOpenCvReady()
                                if (!ready) {
                                    withContext(Dispatchers.Main) {
                                        result.error(
                                            "OPENCV_NOT_READY",
                                            "OpenCV failed to initialize",
                                            mapOf("initFailed" to true),
                                        )
                                    }
                                    return@launch
                                }

                                if (!isProcessing.compareAndSet(false, true)) {
                                    withContext(Dispatchers.Main) {
                                        result.error(
                                            "BUSY",
                                            "Already processing an image. Please wait.",
                                            null,
                                        )
                                    }
                                    return@launch
                                }

                                val args = call.arguments as? Map<*, *>
                                val bytes = args?.get("image") as? ByteArray
                                val totalQuestions = (args?.get("totalQuestions") as? Int) ?: 50
                                val turboMode = args?.get("turboMode") as? Boolean ?: false
                                val sessionLayoutRaw = args?.get("sessionLayout") as? Map<*, *>

                                fun readSessionLayout(raw: Map<*, *>?): OmrProcessor.QrLayoutMetadata? {
                                    if (raw == null || raw.isEmpty()) return null
                                    fun readDouble(key: String): Double {
                                        val value = raw[key] ?: return 0.0
                                        return when (value) {
                                            is Number -> value.toDouble()
                                            else -> value.toString().toDoubleOrNull() ?: 0.0
                                        }
                                    }
                                    fun readInt(key: String): Int {
                                        val value = raw[key] ?: return 0
                                        return when (value) {
                                            is Number -> value.toInt()
                                            else -> value.toString().toIntOrNull() ?: 0
                                        }
                                    }
                                    val templateId = raw["template"]?.toString()?.trim().orEmpty()
                                    val columns = readInt("cols")
                                    val rows = readInt("rows")
                                    val rowHeight = readDouble("rowHeight")
                                    if (templateId.isEmpty() || columns <= 0 || rows <= 0 || rowHeight <= 0.0) {
                                        return null
                                    }
                                    val columnWidth = readDouble("colWidth")
                                    val bubbleSpacingX = readDouble("bubbleSpacingX")
                                    return OmrProcessor.QrLayoutMetadata(
                                        templateId = templateId,
                                        columns = columns,
                                        rows = rows,
                                        gridTop = readDouble("gridTop").takeIf { it > 0.0 } ?: 276.0,
                                        gridBottom = readDouble("gridBottom").takeIf { it > 0.0 } ?: 770.0,
                                        rowHeight = rowHeight,
                                        columnWidth = columnWidth.takeIf { it > 0.0 }
                                            ?: (539.0 / columns),
                                        bubbleSpacingX = bubbleSpacingX.takeIf { it > 0.0 } ?: 17.0,
                                    )
                                }

                                val config = OmrProcessor.ProcessConfig(
                                    totalQuestions = totalQuestions,
                                    sessionLayout = readSessionLayout(sessionLayoutRaw),
                                    turboMode = turboMode,
                                )

                                if (bytes == null || bytes.isEmpty()) {
                                    isProcessing.set(false)
                                    withContext(Dispatchers.Main) {
                                        result.error("INVALID_INPUT", "No image data provided", null)
                                    }
                                    return@launch
                                }

                                if (bytes.size > MAX_IMAGE_SIZE_BYTES) {
                                    isProcessing.set(false)
                                    withContext(Dispatchers.Main) {
                                        result.error(
                                            "IMAGE_TOO_LARGE",
                                            "Image size ${bytes.size / 1024 / 1024}MB exceeds maximum",
                                            null,
                                        )
                                    }
                                    return@launch
                                }

                                if (!checkMemoryAvailable()) {
                                    isProcessing.set(false)
                                    withContext(Dispatchers.Main) {
                                        result.error("LOW_MEMORY", "Device memory too low", null)
                                    }
                                    return@launch
                                }

                                try {
                                    val processingResult = withTimeout(NATIVE_PROCESS_TIMEOUT_MS) {
                                        omrProcessor.processImage(bytes, config)
                                    }
                                    val jsonResult = processingResult.toJson().toString()
                                    withContext(Dispatchers.Main) {
                                        result.success(jsonResult)
                                    }
                                } catch (e: TimeoutCancellationException) {
                                    Log.e(TAG, "processWithConfig timed out after ${NATIVE_PROCESS_TIMEOUT_MS}ms")
                                    withContext(Dispatchers.Main) {
                                        result.error(
                                            "PROCESS_TIMEOUT",
                                            "Scan processing timed out",
                                            null,
                                        )
                                    }
                                } catch (e: OutOfMemoryError) {
                                    Log.e(TAG, "Out of memory: ${e.message}", e)
                                    System.gc()
                                    withContext(Dispatchers.Main) {
                                        result.error("OUT_OF_MEMORY", "Device ran out of memory", null)
                                    }
                                } catch (e: Exception) {
                                    Log.e(TAG, "Processing error: ${e.message}", e)
                                    withContext(Dispatchers.Main) {
                                        result.error("PROCESS_ERROR", e.message, e.stackTraceToString())
                                    }
                                } finally {
                                    isProcessing.set(false)
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "processWithConfig handler error: ${e.message}", e)
                                isProcessing.set(false)
                                withContext(Dispatchers.Main) {
                                    result.error("PROCESS_ERROR", e.message, null)
                                }
                            }
                        }
                    }

                    "ping" -> {
                        result.success(if (syncOpenCvFlag()) "pong" else "not_ready")
                    }

                    // Fast status check — never blocks. Kick off load in background if needed.
                    "isReady" -> {
                        val ready = syncOpenCvFlag()
                        if (!ready) {
                            kickOffOpenCvInit()
                        }
                        Log.d(
                            TAG,
                            "isReady reply: ready=$ready activity=$openCvInitialized runtime=${OpenCvRuntime.isInitialized}",
                        )
                        result.success(ready)
                    }

                    "getInitError" -> {
                        result.success(
                            mapOf(
                                "ready" to syncOpenCvFlag(),
                                "error" to (OpenCvRuntime.lastError ?: ""),
                            ),
                        )
                    }

                    "retryInit" -> {
                        processingScope.launch {
                            try {
                                val ready = if (syncOpenCvFlag()) {
                                    true
                                } else {
                                    // Teacher-facing Retry: force a fresh load cycle.
                                    awaitOpenCvReady(forceRestart = true)
                                }
                                withContext(Dispatchers.Main) {
                                    result.success(ready)
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "retryInit error: ${e.message}", e)
                                withContext(Dispatchers.Main) {
                                    result.success(syncOpenCvFlag())
                                }
                            }
                        }
                    }

                    "ensureReady" -> {
                        processingScope.launch {
                            try {
                                val ready = withTimeoutOrNull(OPEN_CV_READY_WAIT_MS) {
                                    awaitOpenCvReady()
                                } ?: false
                                withContext(Dispatchers.Main) {
                                    result.success(ready || syncOpenCvFlag())
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "ensureReady error: ${e.message}", e)
                                withContext(Dispatchers.Main) {
                                    result.success(syncOpenCvFlag())
                                }
                            }
                        }
                    }

                    "getDeviceInfo" -> {
                        val runtime = Runtime.getRuntime()
                        val used = runtime.totalMemory() - runtime.freeMemory()
                        val remainingMb = (runtime.maxMemory() - used) / 1024 / 1024
                        val tier = DeviceScanTier.warm(this)
                        val info = mapOf(
                            "freeMemoryMB" to runtime.freeMemory() / 1024 / 1024,
                            "remainingMemoryMB" to remainingMb,
                            "maxMemoryMB" to runtime.maxMemory() / 1024 / 1024,
                            "totalMemoryMB" to runtime.totalMemory() / 1024 / 1024,
                            "processorCount" to runtime.availableProcessors(),
                            "isProcessing" to isProcessing.get(),
                            "openCvReady" to syncOpenCvFlag(),
                            "openCvError" to (OpenCvRuntime.lastError ?: ""),
                            "scanTier" to tier.name,
                            "heapClassMb" to DeviceScanTier.cachedHeapClassMb(),
                            "captureWidth" to tier.captureSize.width,
                            "captureHeight" to tier.captureSize.height,
                            "decodeMaxDimension" to tier.decodeMaxDimension,
                        )
                        result.success(info)
                    }

                    "detectSheet" -> {
                        if (!syncOpenCvFlag()) {
                            result.notImplemented()
                            return@setMethodCallHandler
                        }

                        val bytes = call.arguments as? ByteArray
                        if (bytes == null || bytes.isEmpty()) {
                            result.error("INVALID_INPUT", "No image data provided", null)
                            return@setMethodCallHandler
                        }

                        processingScope.launch {
                            try {
                                val detection = omrProcessor.detectSheet(bytes)
                                withContext(Dispatchers.Main) {
                                    result.success(detection.toMap())
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Sheet detection error: ${e.message}", e)
                                withContext(Dispatchers.Main) {
                                    result.error("DETECT_SHEET_ERROR", e.message, e.stackTraceToString())
                                }
                            }
                        }
                    }

                    "analyzeImageQuality" -> {
                        if (!syncOpenCvFlag()) {
                            result.notImplemented()
                            return@setMethodCallHandler
                        }

                        val bytes = call.arguments as? ByteArray
                        if (bytes == null || bytes.isEmpty()) {
                            result.error("INVALID_INPUT", "No image data provided", null)
                            return@setMethodCallHandler
                        }

                        processingScope.launch {
                            try {
                                val quality = omrProcessor.analyzeImageQuality(bytes)
                                withContext(Dispatchers.Main) {
                                    result.success(quality)
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Quality analysis error: ${e.message}", e)
                                withContext(Dispatchers.Main) {
                                    result.error("ANALYZE_QUALITY_ERROR", e.message, e.stackTraceToString())
                                }
                            }
                        }
                    }

                    else -> {
                        result.notImplemented()
                    }
                }
            }
    }

    override fun onResume() {
        super.onResume()
        if (!syncOpenCvFlag()) {
            kickOffOpenCvInit()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        ScannerCameraRegistry.clear()
        processingScope.cancel()
    }
}
