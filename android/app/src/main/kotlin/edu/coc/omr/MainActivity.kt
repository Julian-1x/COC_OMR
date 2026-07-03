package edu.coc.omr

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.opencv.android.OpenCVLoader
import android.util.Log
import kotlinx.coroutines.*
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity: FlutterActivity() {
    private val CHANNEL = "opencv"
    private val TAG = "OpenCV"
    private var openCvInitialized = false
    private val omrProcessor by lazy { OmrProcessor() }
    private val processingScope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    
    // Concurrent processing limits for low-end devices
    private val isProcessing = AtomicBoolean(false)
    private var openCvInitJob: Job? = null
    private var openCvReadyDeferred: CompletableDeferred<Boolean>? = null
    private val MAX_OPENCV_LOAD_ATTEMPTS = 30
    private val MAX_IMAGE_SIZE_BYTES = 20 * 1024 * 1024  // 20MB max
    private val MIN_FREE_MEMORY_MB = 50

    private fun initializeOpenCv(forceRestart: Boolean = false) {
        if (openCvInitialized) {
            return
        }

        if (forceRestart) {
            openCvInitJob?.cancel()
            openCvInitJob = null
            openCvReadyDeferred?.cancel()
            openCvReadyDeferred = null
        } else if (openCvInitJob?.isActive == true) {
            return
        }

        val deferred = CompletableDeferred<Boolean>()
        openCvReadyDeferred = deferred

        openCvInitJob = processingScope.launch {
            var attempt = 0
            while (!openCvInitialized && isActive && attempt < MAX_OPENCV_LOAD_ATTEMPTS) {
                attempt++
                val loaded = withContext(Dispatchers.Default) {
                    OpenCVLoader.initLocal()
                }
                if (loaded) {
                    Log.i(TAG, "OpenCV loaded successfully (attempt $attempt)")
                    openCvInitialized = true
                    break
                }

                Log.e(
                    TAG,
                    "OpenCV load failed (attempt $attempt/$MAX_OPENCV_LOAD_ATTEMPTS)",
                )
                if (attempt < MAX_OPENCV_LOAD_ATTEMPTS) {
                    val delayMs = when {
                        attempt <= 5 -> 0L
                        attempt <= 10 -> 200L
                        else -> minOf(500L * (attempt - 10), 2000L)
                    }
                    if (delayMs > 0) {
                        delay(delayMs)
                    }
                }
            }

            if (!openCvInitialized) {
                Log.e(TAG, "OpenCV failed to load after $MAX_OPENCV_LOAD_ATTEMPTS attempts")
            }
            deferred.complete(openCvInitialized)
        }
    }

    private suspend fun awaitOpenCvReady(): Boolean {
        if (openCvInitialized) {
            return true
        }
        initializeOpenCv()
        return openCvReadyDeferred?.await() ?: false
    }

    private fun checkMemoryAvailable(): Boolean {
        val runtime = Runtime.getRuntime()
        val freeMemoryMB = runtime.freeMemory() / 1024 / 1024
        val maxMemoryMB = runtime.maxMemory() / 1024 / 1024
        val totalMemoryMB = runtime.totalMemory() / 1024 / 1024
        
        Log.d(TAG, "Memory: free=${freeMemoryMB}MB, total=${totalMemoryMB}MB, max=${maxMemoryMB}MB")
        
        if (freeMemoryMB < MIN_FREE_MEMORY_MB) {
            // Try garbage collection
            System.gc()
            val afterGcFree = runtime.freeMemory() / 1024 / 1024
            Log.d(TAG, "After GC: free=${afterGcFree}MB")
            return afterGcFree >= MIN_FREE_MEMORY_MB / 2
        }
        return true
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        initializeOpenCv()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        ScannerCameraPlugin.register(flutterEngine, this)

        initializeOpenCv()
        
        // Setup method channel for OpenCV
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "process" -> {
                        if (!openCvInitialized) {
                            result.error("OPENCV_NOT_READY", "OpenCV is not initialized yet", null)
                            return@setMethodCallHandler
                        }
                        
                        // Check if already processing (prevent concurrent processing on low-end devices)
                        if (!isProcessing.compareAndSet(false, true)) {
                            result.error("BUSY", "Already processing an image. Please wait.", null)
                            return@setMethodCallHandler
                        }
                        
                        val bytes = call.arguments as? ByteArray
                        if (bytes == null || bytes.isEmpty()) {
                            isProcessing.set(false)
                            result.error("INVALID_INPUT", "No image data provided", null)
                            return@setMethodCallHandler
                        }
                        
                        // Validate image size
                        if (bytes.size > MAX_IMAGE_SIZE_BYTES) {
                            isProcessing.set(false)
                            result.error("IMAGE_TOO_LARGE", 
                                "Image size ${bytes.size / 1024 / 1024}MB exceeds maximum ${MAX_IMAGE_SIZE_BYTES / 1024 / 1024}MB", 
                                null)
                            return@setMethodCallHandler
                        }
                        
                        // Check memory before processing
                        if (!checkMemoryAvailable()) {
                            isProcessing.set(false)
                            result.error("LOW_MEMORY", 
                                "Device memory too low. Please close other apps and try again.", 
                                null)
                            return@setMethodCallHandler
                        }
                        
                        // Process asynchronously
                        processingScope.launch {
                            try {
                                val processingResult = omrProcessor.processImage(bytes)
                                val jsonResult = processingResult.toJson().toString()
                                
                                withContext(Dispatchers.Main) {
                                    result.success(jsonResult)
                                }
                            } catch (e: OutOfMemoryError) {
                                Log.e(TAG, "Out of memory: ${e.message}", e)
                                System.gc()
                                withContext(Dispatchers.Main) {
                                    result.error("OUT_OF_MEMORY", 
                                        "Device ran out of memory. Please close other apps.", 
                                        null)
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Processing error: ${e.message}", e)
                                withContext(Dispatchers.Main) {
                                    result.error("PROCESS_ERROR", e.message, e.stackTraceToString())
                                }
                            } finally {
                                isProcessing.set(false)
                            }
                        }
                    }
                    
                    "processWithConfig" -> {
                        if (!openCvInitialized) {
                            result.error("OPENCV_NOT_READY", "OpenCV is not initialized yet", null)
                            return@setMethodCallHandler
                        }
                        
                        // Check if already processing
                        if (!isProcessing.compareAndSet(false, true)) {
                            result.error("BUSY", "Already processing an image. Please wait.", null)
                            return@setMethodCallHandler
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
                            result.error("INVALID_INPUT", "No image data provided", null)
                            return@setMethodCallHandler
                        }
                        
                        // Validate image size
                        if (bytes.size > MAX_IMAGE_SIZE_BYTES) {
                            isProcessing.set(false)
                            result.error("IMAGE_TOO_LARGE", 
                                "Image size ${bytes.size / 1024 / 1024}MB exceeds maximum", 
                                null)
                            return@setMethodCallHandler
                        }
                        
                        // Check memory
                        if (!checkMemoryAvailable()) {
                            isProcessing.set(false)
                            result.error("LOW_MEMORY", "Device memory too low", null)
                            return@setMethodCallHandler
                        }
                        
                        processingScope.launch {
                            try {
                                val processingResult = omrProcessor.processImage(bytes, config)
                                val jsonResult = processingResult.toJson().toString()
                                
                                withContext(Dispatchers.Main) {
                                    result.success(jsonResult)
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
                        }
                    }
                    
                    "ping" -> {
                        result.success(if (openCvInitialized) "pong" else "not_ready")
                    }
                    
                    "isReady" -> {
                        if (!openCvInitialized) {
                            initializeOpenCv()
                        }
                        result.success(openCvInitialized)
                    }

                    "retryInit" -> {
                        if (!openCvInitialized) {
                            initializeOpenCv(forceRestart = true)
                        }
                        result.success(null)
                    }

                    "ensureReady" -> {
                        processingScope.launch {
                            val ready = awaitOpenCvReady()
                            withContext(Dispatchers.Main) {
                                result.success(ready)
                            }
                        }
                    }
                    
                    "getDeviceInfo" -> {
                        // Return device info for adaptive processing decisions on Flutter side
                        val runtime = Runtime.getRuntime()
                        val info = mapOf(
                            "freeMemoryMB" to runtime.freeMemory() / 1024 / 1024,
                            "maxMemoryMB" to runtime.maxMemory() / 1024 / 1024,
                            "totalMemoryMB" to runtime.totalMemory() / 1024 / 1024,
                            "processorCount" to runtime.availableProcessors(),
                            "isProcessing" to isProcessing.get()
                        )
                        result.success(info)
                    }

                    "detectSheet" -> {
                        if (!openCvInitialized) {
                            // Let Flutter fall back to Dart-side heuristics until OpenCV is ready.
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
                        if (!openCvInitialized) {
                            // Let Flutter fall back to Dart-side heuristics until OpenCV is ready.
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
        if (!openCvInitialized) {
            initializeOpenCv()
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        ScannerCameraRegistry.clear()
        processingScope.cancel()
    }
}
