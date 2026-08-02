package edu.coc.omr

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.util.Base64
import android.util.Log
import androidx.exifinterface.media.ExifInterface
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import org.opencv.android.Utils
import org.opencv.core.*
import org.opencv.imgproc.Imgproc
import org.opencv.objdetect.QRCodeDetector
import org.json.JSONObject
import org.json.JSONArray
import kotlin.math.*
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * High-accuracy OMR (Optical Mark Recognition) processor using OpenCV.
 * Optimized for low-end devices with memory management and adaptive processing.
 * 
 * Detection pipeline:
 * 1. Preprocess image (downscale if needed, grayscale, blur, threshold)
 * 2. Detect 4 corner markers for alignment (black squares with white centers)
 * 3. Apply perspective transform to correct skew
 * 4. Detect timing marks for precise grid alignment
 * 5. Auto-calibrate fill threshold using calibration marks
 * 6. Detect and decode QR code
 * 7. Read OMR ID (4-digit student ID)
 * 8. Read answer bubbles (A-E per question)
 * 9. Cross-validate and calculate confidence scores
 */
class OmrProcessor(
    private val appContext: Context? = null,
) {
    companion object {
        private const val TAG = "OmrProcessor"
        
        // Standard output size after perspective transform (A4 at 72 DPI)
        private const val OUTPUT_WIDTH = 595
        private const val OUTPUT_HEIGHT = 842
        
        // Corner marker specs (from answer_sheet_generator.dart)
        private const val CORNER_MARKER_SIZE = 20.0  // points
        private const val CORNER_OFFSET = 8.0  // points from edge
        
        // Timing mark specs
        private const val TIMING_MARK_SIZE = 6.0  // points
        private const val TIMING_MARK_SPACING = 80.0  // points between marks
        private const val TIMING_MARK_EDGE_OFFSET = 8.0  // points from edge
        
        // Margins (points)
        private const val MARGIN_LEFT = 28.0
        private const val MARGIN_RIGHT = 28.0
        private const val MARGIN_TOP = 34.0
        private const val MARGIN_BOTTOM = 28.0
        
        // Bubble specifications
        private const val BUBBLE_DIAMETER = 11.5  // points
        private const val BUBBLE_BORDER = 1.2  // points
        private const val DEFAULT_FILL_THRESHOLD = 0.33  // Slightly more tolerant of light pencil shading
        
        // OMR ID section layout (from OmrPageConstants)
        private const val OMR_ID_COLUMNS = 4
        private const val OMR_ID_ROWS = 10
        private const val OMR_ID_TOP = 114.0  // Fixed Y position
        private const val OMR_ID_HEIGHT = 136.0
        private const val OMR_ID_COLUMN_SPACING = 50.0  // center-to-center
        private const val OMR_ID_ROW_SPACING = 12.0  // center-to-center
        private const val OMR_ID_FIRST_COLUMN_X = 222.5  // centered first column
        private const val OMR_ID_FIRST_ROW_Y = 134.0  // center of first row (digit 0)
        
        // Calibration marks (from OmrPageConstants)
        private const val CALIBRATION_Y = 810.0
        private const val CALIBRATION_FILLED_X = 80.0
        private const val CALIBRATION_EMPTY_X = 110.0
        private const val CALIBRATION_BUBBLE_SIZE = 10.0
        
        // Answer section
        private const val ANSWER_OPTIONS = 5  // A, B, C, D, E

        // Fixed answer grid positions (from OmrPageConstants in omr_template_specs.dart)
        // These match the template specs exactly
        private const val ANSWER_GRID_TOP = 276.0  // first answer row origin after A-E labels
        private const val ANSWER_GRID_BOTTOM = 770.0  // bottom of answer rows before footer
        private const val ANSWER_GRID_LEFT = 28.0  // MARGIN_LEFT
        private const val ANSWER_GRID_RIGHT = 567.0  // PAGE_WIDTH - MARGIN_RIGHT
        private const val ANSWER_GRID_WIDTH = ANSWER_GRID_RIGHT - ANSWER_GRID_LEFT  // 539
        private const val QUESTION_NUMBER_WIDTH = 16.0
        private const val ANSWER_COLUMN_INSET = 6.0
        private const val ANSWER_NUMBER_BUBBLE_GAP = 6.0
        
        // Row mark positions (for alignment validation)
        private const val ROW_MARK_X = 18.0  // Left edge marks
        private const val ROW_MARK_SIZE = 4.0
        
        // Adaptive decode ceilings live on DeviceScanTier; these are fallbacks only.
        private const val MAX_IMAGE_DIMENSION = 2000
        private const val LOW_MEMORY_THRESHOLD_MB = 120
        private const val PROCESSING_TIMEOUT_MS = 15000L
        private const val MAX_IMAGE_SIZE_BYTES = 16 * 1024 * 1024
        
        // Low-quality camera handling constants
        private const val MIN_BLUR_THRESHOLD = 100.0  // Laplacian variance threshold for blur detection
        private const val MIN_CONTRAST_RATIO = 1.5  // Minimum contrast ratio for reliable detection
        private const val NOISE_THRESHOLD = 15.0  // Max acceptable noise level
        private const val TIMING_MARK_FAIL_THRESHOLD = 0.40  // Below this, alignment is too poor to grade
        /** Below this mean gray (0–255) after enhancement, refuse to grade. */
        private const val HARD_DARK_BRIGHTNESS = 42.0
        /** Original capture darker than this gets stronger safe enhancement. */
        private const val DARK_CAPTURE_BRIGHTNESS = 80.0
        /** Extra bubble fill threshold when capture was dark (reduces false marks). */
        private const val DARK_FILL_THRESHOLD_BOOST = 0.06
        /** If fewer than this fraction of questions yield a mark, treat as grid misalignment. */
        private const val MIN_ANSWER_YIELD = 0.12
        /** Local refine radius (px on 595-wide warp) around predicted bubble centers. */
        private const val BUBBLE_REFINE_RADIUS_PX = 2

        // Printed QR box in page points (OmrPageConstants: 80pt square, top-right),
        // padded so a slightly skewed capture still contains the whole symbol.
        private const val QR_BOX_LEFT = 470.0
        private const val QR_BOX_TOP = 20.0
        private const val QR_BOX_RIGHT = 582.0
        private const val QR_BOX_BOTTOM = 128.0

        /** Magnification of the source-resolution QR crop, best first. */
        private val QR_SOURCE_CROP_SCALES = doubleArrayOf(5.0, 3.0, 8.0)
    }
    
    /**
     * Layout metadata extracted from QR payload v2
     */
    data class QrLayoutMetadata(
        val templateId: String,
        val columns: Int,
        val rows: Int,
        val gridTop: Double,
        val gridBottom: Double,
        val rowHeight: Double,
        val columnWidth: Double,
        val bubbleSpacingX: Double
    )

    /** Exam turbo: session-locked layout + faster pipeline without QR per sheet. */
    data class ProcessConfig(
        val totalQuestions: Int = 50,
        val sessionLayout: QrLayoutMetadata? = null,
        val turboMode: Boolean = false,
    )
    
    // Image quality assessment result
    data class ImageQuality(
        val isAcceptable: Boolean,
        val blurScore: Double,      // Higher = sharper (Laplacian variance)
        val contrastScore: Double,  // Higher = better contrast
        val brightnessScore: Double, // 0-255, ideal ~120-180
        val noiseScore: Double,     // Lower = less noise
        val issues: List<String>
    )

    data class QuickSheetDetectionResult(
        val sheetDetected: Boolean,
        val isAligned: Boolean,
        val hasGoodLighting: Boolean,
        val confidence: Double,
        val hint: String?
    ) {
        fun toMap(): Map<String, Any?> {
            return mapOf(
                "sheetDetected" to sheetDetected,
                "isAligned" to isAligned,
                "hasGoodLighting" to hasGoodLighting,
                "confidence" to confidence,
                "hint" to hint
            )
        }
    }
    
    // Processing quality enum for adaptive processing
    enum class ProcessingQuality {
        HIGH,      // Full processing (bilateral filter, full contour search)
        BALANCED,  // Reduced filter radius, limited search
        FAST       // Skip bilateral filter, use simple threshold
    }
    
    // QR Code detector
    private val qrDetector = QRCodeDetector()
    
    data class ProcessingResult(
        val success: Boolean,
        val omrId: String?,
        val answers: Map<Int, String>,
        val confidence: Double,
        val qrData: String?,
        val errorMessage: String?,
        val debugInfo: Map<String, Any>
    ) {
        fun toJson(): JSONObject {
            return JSONObject().apply {
                put("success", success)
                put("omrId", omrId)
                put("answers", JSONObject(answers.mapKeys { it.key.toString() }))
                put("confidence", confidence)
                put("qrData", qrData)
                put("errorMessage", errorMessage)
                put("debugInfo", JSONObject(debugInfo.mapValues { entry ->
                    jsonCompatValue(entry.value)
                }))
            }
        }

        private fun jsonCompatValue(value: Any?): Any? {
            return when (value) {
                null -> JSONObject.NULL
                is Number, is Boolean, is String -> value
                is Map<*, *> -> JSONObject(value.entries.associate { (k, v) ->
                    k.toString() to jsonCompatValue(v)
                })
                is List<*> -> JSONArray().also { arr ->
                    value.forEach { arr.put(jsonCompatValue(it)) }
                }
                is Array<*> -> JSONArray().also { arr ->
                    value.forEach { arr.put(jsonCompatValue(it)) }
                }
                else -> value.toString()
            }
        }
    }
    
    data class DetectedCorners(
        val topLeft: Point,
        val topRight: Point,
        val bottomLeft: Point,
        val bottomRight: Point
    ) {
        fun isValid(): Boolean {
            // Check that corners form a reasonable quadrilateral
            val width1 = distance(topLeft, topRight)
            val width2 = distance(bottomLeft, bottomRight)
            val height1 = distance(topLeft, bottomLeft)
            val height2 = distance(topRight, bottomRight)
            
            // Phone perspective often stretches one edge; 0.72 still rejects crossed/bad quads
            // while accepting real desk captures that 0.80 wrongly discarded.
            val widthRatio = minOf(width1, width2) / maxOf(width1, width2)
            val heightRatio = minOf(height1, height2) / maxOf(height1, height2)
            
            return widthRatio > 0.72 && heightRatio > 0.72
        }
        
        private fun distance(p1: Point, p2: Point): Double {
            return sqrt((p2.x - p1.x).pow(2) + (p2.y - p1.y).pow(2))
        }
    }
    
    data class BubbleResult(
        val filled: Boolean,
        val fillPercentage: Double,
        val confidence: Double,
        val centerX: Double,
        val centerY: Double
    )
    
    data class GridCalibration(
        val fillThreshold: Double,
        val emptyAverage: Double,
        val filledAverage: Double,
        val isCalibrated: Boolean
    )
    
    /**
     * OMR ID read outcome. [needsReview] is set when 3 of 4 columns are clean and one
     * column was ambiguous/blank — [id] then holds a best-guess so roster lookup can
     * still match, with [ambiguousColumn] telling the review UI which digit to verify.
     */
    data class OmrIdReadResult(
        val id: String,
        val confidence: Double,
        val needsReview: Boolean,
        val ambiguousColumn: Int
    )
    
    private val baseScanTier: DeviceScanTier by lazy {
        val ctx = appContext
        if (ctx != null) {
            DeviceScanTier.warm(ctx)
        } else {
            DeviceScanTier.cachedOrNull()
                ?: DeviceScanTier.fromHeapClassMb(
                    (Runtime.getRuntime().maxMemory() / 1024 / 1024).toInt(),
                )
        }
    }

    /**
     * Determine processing quality from remaining heap capacity (not freeMemory alone).
     */
    private fun determineProcessingQuality(): ProcessingQuality {
        val remainingMB = DeviceScanTier.remainingHeapMb().toInt()
        val maxMemoryMB = (Runtime.getRuntime().maxMemory() / 1024 / 1024).toInt()

        Log.d(TAG, "Memory: remaining=${remainingMB}MB / max=${maxMemoryMB}MB tier=$baseScanTier")

        return when {
            remainingMB < 48 || baseScanTier == DeviceScanTier.LOW -> ProcessingQuality.FAST
            remainingMB < LOW_MEMORY_THRESHOLD_MB || baseScanTier == DeviceScanTier.MID ->
                ProcessingQuality.BALANCED
            else -> ProcessingQuality.HIGH
        }
    }

    /** Longest decode edge from device tier, optionally tightened under memory pressure. */
    private fun maxDecodeDimension(quality: ProcessingQuality, turboMode: Boolean): Int {
        val tier = DeviceScanTier.forProcessing(baseScanTier)
        var maxDim = tier.decodeMaxDimension
        if (quality == ProcessingQuality.FAST) {
            maxDim = minOf(maxDim, DeviceScanTier.LOW.decodeMaxDimension)
        } else if (quality == ProcessingQuality.BALANCED) {
            maxDim = minOf(maxDim, DeviceScanTier.MID.decodeMaxDimension)
        }
        // Turbo skips the slowest filters but still keeps enough pixels for marks/bubbles.
        if (turboMode) {
            maxDim = minOf(maxDim, DeviceScanTier.HIGH.decodeMaxDimension)
        }
        return maxDim
    }
    
    /**
     * Check if we have enough memory to process.
     * Uses remaining capacity to [Runtime.maxMemory], not only freeMemory() in the
     * currently committed heap (which is often low and rejected scans incorrectly).
     */
    private fun checkMemoryAvailable(requiredMB: Int = 40): Boolean {
        val runtime = Runtime.getRuntime()
        fun remainingHeapMb(): Long {
            val max = runtime.maxMemory()
            val used = runtime.totalMemory() - runtime.freeMemory()
            return (max - used) / (1024 * 1024)
        }

        var remaining = remainingHeapMb()
        Log.d(TAG, "Memory check: remaining=${remaining}MB required≈${requiredMB}MB")
        if (remaining < requiredMB) {
            Log.w(TAG, "Low memory warning: ${remaining}MB remaining, ${requiredMB}MB preferred")
            System.gc()
            remaining = remainingHeapMb()
            return remaining >= (requiredMB / 2).coerceAtLeast(24)
        }
        return true
    }
    
    /**
     * Downscale image if needed for memory efficiency
     */
    private fun downscaleIfNeeded(bitmap: Bitmap, maxDimension: Int = MAX_IMAGE_DIMENSION): Bitmap {
        val width = bitmap.width
        val height = bitmap.height
        val maxDim = maxOf(width, height)
        
        if (maxDim <= maxDimension) {
            Log.d(TAG, "Image size OK: ${width}x${height}, no downscaling needed")
            return bitmap
        }
        
        val scale = maxDimension.toFloat() / maxDim
        val newWidth = (width * scale).toInt()
        val newHeight = (height * scale).toInt()
        
        Log.d(TAG, "Downscaling: ${width}x${height} -> ${newWidth}x${newHeight} (scale: ${String.format("%.2f", scale)})")
        
        val scaledBitmap = Bitmap.createScaledBitmap(bitmap, newWidth, newHeight, true)
        
        // Release original if we created a new one
        if (scaledBitmap !== bitmap) {
            bitmap.recycle()
        }
        
        return scaledBitmap
    }
    
    /**
     * Main processing entry point - optimized for low-end devices
     */
    fun processImage(imageBytes: ByteArray, totalQuestions: Int = 50): ProcessingResult {
        return processImage(imageBytes, ProcessConfig(totalQuestions = totalQuestions))
    }

    fun processImage(imageBytes: ByteArray, config: ProcessConfig): ProcessingResult {
        val totalQuestions = config.totalQuestions
        val sessionLayout = config.sessionLayout
        val turboMode = config.turboMode
        val debugInfo = mutableMapOf<String, Any>()
        val pipelineStages = mutableListOf<String>()
        val startTime = System.currentTimeMillis()
        debugInfo["turboMode"] = turboMode
        debugInfo["layoutFromSession"] = sessionLayout != null

        fun stageOk(label: String) {
            val line = "✓ $label"
            pipelineStages.add(line)
            Log.i(TAG, line)
        }

        fun stageFail(label: String, why: String): ProcessingResult {
            val line = "✗ $label — $why"
            pipelineStages.add(line)
            debugInfo["pipelineStages"] = pipelineStages.toList()
            debugInfo["failedStage"] = label
            debugInfo["failedWhy"] = why
            Log.e(TAG, line)
            return errorResult(why, debugInfo)
        }
        
        // Validate input size
        if (imageBytes.size > MAX_IMAGE_SIZE_BYTES) {
            Log.e(TAG, "Image too large: ${imageBytes.size / 1024 / 1024}MB > ${MAX_IMAGE_SIZE_BYTES / 1024 / 1024}MB limit")
            return errorResult("Image too large. Please capture at lower resolution.", debugInfo)
        }
        
        debugInfo["inputSizeKB"] = imageBytes.size / 1024
        
        // Check memory before processing
        if (!checkMemoryAvailable()) {
            return errorResult("Device memory too low. Please close other apps and try again.", debugInfo)
        }
        System.gc()
        
        // Turbo keeps corner detection accurate but avoids the slowest quality path.
        val quality = if (turboMode && sessionLayout != null) {
            val memQuality = determineProcessingQuality()
            if (memQuality == ProcessingQuality.FAST) ProcessingQuality.FAST else ProcessingQuality.BALANCED
        } else {
            determineProcessingQuality()
        }
        debugInfo["processingQuality"] = quality.name
        val decodeMax = maxDecodeDimension(quality, turboMode)
        val processTier = DeviceScanTier.forProcessing(baseScanTier)
        debugInfo["decodeMaxDimension"] = decodeMax
        debugInfo["scanTier"] = processTier.name
        debugInfo["baseScanTier"] = baseScanTier.name
        Log.d(
            TAG,
            "Using quality=$quality decodeMax=$decodeMax tier=$processTier " +
                "(base=$baseScanTier turbo=$turboMode)",
        )
        
        // Mats for cleanup (use nullable for safety)
        var originalMat: Mat? = null
        var grayMat: Mat? = null
        var warpedMat: Mat? = null
        var thresholdMat: Mat? = null
        var bitmap: Bitmap? = null
        
        try {
            // Step 1: Decode image (respect EXIF rotation from camera capture)
            bitmap = decodeBitmapForAnalysis(imageBytes, decodeMax)
            if (bitmap == null) {
                return stageFail("Camera Image Loaded", "Failed to decode image bytes")
            }
            stageOk("Camera Image Loaded (${bitmap.width}x${bitmap.height})")

            debugInfo["imageWidth"] = bitmap.width
            debugInfo["imageHeight"] = bitmap.height
            debugInfo["decodeMs"] = System.currentTimeMillis() - startTime
            debugInfo["exifApplied"] = true
            stageOk("EXIF Rotation Applied")
            
            // Check timeout
            if (System.currentTimeMillis() - startTime > PROCESSING_TIMEOUT_MS / 3) {
                Log.w(TAG, "Slow image decode - device may be struggling")
            }
            
            // Step 2: Convert to OpenCV Mat
            originalMat = Mat()
            Utils.bitmapToMat(bitmap, originalMat)
            
            // We can release bitmap now to free memory
            bitmap.recycle()
            bitmap = null
            
            // Step 3: Convert to grayscale
            grayMat = Mat()
            Imgproc.cvtColor(originalMat, grayMat, Imgproc.COLOR_RGBA2GRAY)
            
            // Release original since we have grayscale
            originalMat.release()
            originalMat = null
            
            // Step 3.5: Assess image quality (for low-quality camera handling)
            val imageQuality = assessImageQuality(grayMat)
            debugInfo["blurScore"] = imageQuality.blurScore
            debugInfo["contrastScore"] = imageQuality.contrastScore
            debugInfo["brightnessScore"] = imageQuality.brightnessScore
            debugInfo["noiseScore"] = imageQuality.noiseScore
            debugInfo["qualityIssues"] = imageQuality.issues
            
            Log.d(TAG, "Image quality: blur=${String.format("%.1f", imageQuality.blurScore)}, " +
                    "contrast=${String.format("%.2f", imageQuality.contrastScore)}, " +
                    "brightness=${String.format("%.1f", imageQuality.brightnessScore)}")
            
            val cornersStartMs = System.currentTimeMillis()
            val wasDarkCapture = imageQuality.brightnessScore < DARK_CAPTURE_BRIGHTNESS
            debugInfo["wasDarkCapture"] = wasDarkCapture
            if (!imageQuality.isAcceptable && !(turboMode && imageQuality.blurScore >= MIN_BLUR_THRESHOLD * 0.5)) {
                // Try to enhance the image before giving up (skipped in turbo when sharp enough)
                Log.w(TAG, "Image quality issues: ${imageQuality.issues}. Attempting enhancement...")
                enhanceImageForLowQualityCamera(grayMat, imageQuality)
                debugInfo["imageEnhanced"] = true
            }
            val postEnhanceBrightness = Core.mean(grayMat).`val`[0]
            debugInfo["postEnhanceBrightness"] = postEnhanceBrightness
            if (postEnhanceBrightness < HARD_DARK_BRIGHTNESS) {
                debugInfo["failureReason"] = "TOO_DARK"
                debugInfo["pipelineStages"] = pipelineStages.toList()
                return stageFail(
                    "Quality Check",
                    "Too dark to scan safely. Turn on the phone light or move to a brighter area.",
                )
            }
            stageOk("Quality Check Passed (blur=${imageQuality.blurScore.toInt()})")
            
            // Step 4: Detect corner markers using quality-appropriate method
            val corners = detectCornerMarkersAdaptive(grayMat, quality, debugInfo)
            if (corners == null || !corners.isValid()) {
                val failureReason = classifyCornerFailure(imageQuality, debugInfo)
                debugInfo["failureReason"] = failureReason
                val errorMsg = buildCornerDetectionErrorMessage(imageQuality, debugInfo, failureReason)
                debugInfo["pipelineStages"] = pipelineStages.toList()
                return stageFail("Corner Detection", errorMsg)
            }
            stageOk("Corner Detection Passed via ${debugInfo["cornerDetectionSucceededVia"]}")
            
            debugInfo["cornersDetected"] = true
            debugInfo["cornerPositions"] = listOf(
                listOf(corners.topLeft.x, corners.topLeft.y),
                listOf(corners.topRight.x, corners.topRight.y),
                listOf(corners.bottomLeft.x, corners.bottomLeft.y),
                listOf(corners.bottomRight.x, corners.bottomRight.y)
            )
            Log.d(TAG, "Corners detected and validated")
            debugInfo["cornersMs"] = System.currentTimeMillis() - cornersStartMs
            
            // Check timeout
            if (System.currentTimeMillis() - startTime > PROCESSING_TIMEOUT_MS * 2 / 3) {
                Log.w(TAG, "Corner detection took long - simplifying remaining steps")
            }
            
            // Step 5: Apply perspective transform
            val warpStartMs = System.currentTimeMillis()
            warpedMat = applyPerspectiveTransform(grayMat, corners)
            debugInfo["warpedSize"] = "${warpedMat.cols()}x${warpedMat.rows()}"
            debugInfo["warpMs"] = System.currentTimeMillis() - warpStartMs
            stageOk("Perspective Warp Successful (${warpedMat.cols()}x${warpedMat.rows()})")
            
            // Step 5.5: Decode the QR from the ORIGINAL frame before releasing it.
            // The 595px warp leaves the printed QR ~80px wide (~1.4px per module),
            // which is mathematically undecodable — crop it at source resolution.
            val sourceQrStartMs = System.currentTimeMillis()
            val sourceQrData = if (quality == ProcessingQuality.FAST && sessionLayout == null) {
                null
            } else {
                decodeQrFromSourceFrame(grayMat, corners, debugInfo)
            }
            debugInfo["sourceQrMs"] = System.currentTimeMillis() - sourceQrStartMs
            debugInfo["sourceQrDetected"] = sourceQrData != null

            // Release grayscale since we have warped
            grayMat.release()
            grayMat = null
            
            // Step 6: Validate alignment using timing marks.
            // Never fake this score — low-memory FAST mode previously skipped checks and
            // graded misaligned warps, which produced empty/wrong answer maps.
            val timingMarkScore = validateTimingMarks(warpedMat, debugInfo)
            debugInfo["timingMarkScore"] = timingMarkScore
            val timingFound = (debugInfo["timingMarksFound"] as? Number)?.toInt() ?: 0
            val timingExpected = (debugInfo["timingMarksExpected"] as? Number)?.toInt() ?: 0
            if (timingMarkScore < TIMING_MARK_FAIL_THRESHOLD) {
                debugInfo["failureReason"] = "TIMING_MARKS"
                debugInfo["cornersDetected"] = true
                attachDebugOverlay(
                    warpedMat = warpedMat,
                    layout = sessionLayout ?: calculateFallbackLayout(totalQuestions),
                    answers = emptyMap(),
                    fillThreshold = DEFAULT_FILL_THRESHOLD,
                    debugInfo = debugInfo,
                )
                return stageFail(
                    "Timing Marks Detected",
                    buildTimingMarkErrorMessage(timingMarkScore, debugInfo),
                )
            }
            stageOk("Timing Marks Detected ($timingFound/$timingExpected, ${(timingMarkScore * 100).toInt()}%)")
            if (timingMarkScore < 0.5) {
                Log.w(TAG, "Low timing mark score: $timingMarkScore - alignment may be off")
            }
            
            // Step 7: Always try QR — needed to reject EvalBee / foreign sheets even in turbo.
            // Session layout still wins for bubble positions when present.
            val qrStartMs = System.currentTimeMillis()
            val qrData = sourceQrData ?: if (quality == ProcessingQuality.FAST && sessionLayout == null) {
                Log.d(TAG, "Skipping QR detection in FAST mode (no session layout)")
                null
            } else {
                detectQRCode(warpedMat, debugInfo)
            }
            debugInfo["qrMs"] = System.currentTimeMillis() - qrStartMs
            debugInfo["qrDetected"] = qrData != null
            debugInfo["qrSkippedForSession"] = false
            debugInfo["sessionLayoutLocked"] = sessionLayout != null

            val qrIdentity = classifyQrIdentity(qrData, debugInfo)
            debugInfo["sheetQrIdentity"] = qrIdentity
            
            // Step 7.5: Layout from session, QR v2, or fallback
            val layout = sessionLayout
                ?: parseQrLayout(qrData)
                ?: calculateFallbackLayout(totalQuestions)
            debugInfo["layoutTemplate"] = layout.templateId
            debugInfo["layoutFromQr"] = sessionLayout == null && layout.templateId != "LEGACY"
            debugInfo["layoutCols"] = layout.columns
            debugInfo["layoutRows"] = layout.rows
            debugInfo["layoutGridTop"] = layout.gridTop
            debugInfo["layoutRowHeight"] = layout.rowHeight
            Log.d(TAG, "Using layout: template=${layout.templateId}, cols=${layout.columns}, rows=${layout.rows}")
            stageOk("Layout Loaded (${layout.templateId}, ${layout.columns}x${layout.rows})")
            
            // Step 8: Auto-calibrate fill threshold using calibration marks in footer
            val calibration = calibrateFillThreshold(warpedMat, debugInfo)
            var fillThreshold = if (calibration.isCalibrated) calibration.fillThreshold else DEFAULT_FILL_THRESHOLD
            if (wasDarkCapture) {
                fillThreshold = (fillThreshold + DARK_FILL_THRESHOLD_BOOST).coerceAtMost(0.55)
                debugInfo["darkFillThresholdBoost"] = DARK_FILL_THRESHOLD_BOOST
            }
            debugInfo["fillThreshold"] = fillThreshold
            debugInfo["calibrationSuccess"] = calibration.isCalibrated
            stageOk(
                "Threshold Calculated (${String.format("%.2f", fillThreshold)}" +
                    if (calibration.isCalibrated) ", calibrated)" else ", default)",
            )
            
            // Step 9: Apply adaptive threshold for bubble detection
            thresholdMat = Mat()
            var blockSize = if (quality == ProcessingQuality.FAST) 11 else 15
            if (blockSize % 2 == 0) blockSize += 1
            Imgproc.adaptiveThreshold(
                warpedMat, thresholdMat,
                255.0,
                Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C,
                Imgproc.THRESH_BINARY_INV,
                blockSize, 4.0
            )
            
            // Step 9.5: Row marks — always run (including LEGACY) for foreign-sheet gate
            val rowMarkValidation = validateRowMarks(warpedMat, layout, debugInfo)
            debugInfo["rowMarkValidation"] = rowMarkValidation
            if (rowMarkValidation < 0.6) {
                Log.w(TAG, "Low row mark validation score: $rowMarkValidation - template mismatch possible")
                debugInfo["templateMismatchWarning"] = true
            }

            // Step 9.6: Reject EvalBee / non-COC paper before reading OMR ID or answers.
            // When the teacher opened the scanner for a COC answer key, session layout is
            // already locked — do not treat unread QR / weak row marks as a foreign sheet.
            if (sessionLayout != null) {
                when (qrIdentity) {
                    "foreign" -> {
                        val foreignApp = debugInfo["sheetQrForeignApp"]?.toString()?.trim()
                        if (!foreignApp.isNullOrEmpty()) {
                            debugInfo["failureReason"] = "FOREIGN_SHEET"
                            debugInfo["sheetOriginClassification"] = "foreign_qr"
                            attachDebugOverlay(warpedMat, layout, emptyMap(), fillThreshold, debugInfo)
                            return stageFail(
                                "Sheet Identity",
                                "This does not look like a COC OMR answer sheet. Print sheets from this app (Prepare → Print Sheets), then scan again.",
                            )
                        }
                        debugInfo["sheetOriginClassification"] = "coc_session"
                        stageOk("Sheet Identity (COC session)")
                    }
                    "coc", "coc_legacy" -> stageOk("Sheet Identity (COC QR)")
                    else -> {
                        debugInfo["sheetOriginClassification"] = "coc_session"
                        stageOk("Sheet Identity (COC session)")
                    }
                }
            } else if (qrIdentity == "foreign") {
                debugInfo["failureReason"] = "FOREIGN_SHEET"
                debugInfo["sheetOriginClassification"] = "foreign_qr"
                attachDebugOverlay(warpedMat, layout, emptyMap(), fillThreshold, debugInfo)
                return stageFail(
                    "Sheet Identity",
                    "This does not look like a COC OMR answer sheet. Print sheets from this app (Prepare → Print Sheets), then scan again.",
                )
            } else if (qrIdentity == "none" || qrIdentity == "unknown") {
                // No COC QR — require our printed geometry (row marks + timing).
                val geometryLooksCoc =
                    timingMarkScore >= 0.85 ||
                    (timingMarkScore >= 0.50 && rowMarkValidation >= 0.55)
                debugInfo["sheetGeometryLooksCoc"] = geometryLooksCoc
                if (!geometryLooksCoc) {
                    debugInfo["failureReason"] = "FOREIGN_SHEET"
                    debugInfo["sheetOriginClassification"] = "foreign_geometry"
                    attachDebugOverlay(warpedMat, layout, emptyMap(), fillThreshold, debugInfo)
                    return stageFail(
                        "Sheet Identity",
                        "This does not look like a COC OMR answer sheet. Use a sheet printed from this app — other OMR apps' papers cannot be graded here.",
                    )
                }
                debugInfo["sheetOriginClassification"] = "coc_geometry"
                stageOk("Sheet Identity (COC geometry)")
            } else {
                debugInfo["sheetOriginClassification"] = "coc_qr"
                stageOk("Sheet Identity (COC QR)")
            }
            
            // Step 10: Detect OMR ID with validation
            val omrIdResult = detectOmrIdWithValidation(thresholdMat, warpedMat, fillThreshold, debugInfo)
            if (omrIdResult != null) {
                debugInfo["omrId"] = omrIdResult.id
                debugInfo["omrIdConfidence"] = omrIdResult.confidence
                stageOk("OMR ID Read (${omrIdResult.id})")
            } else {
                debugInfo["failureReason"] = "OMR_ID"
                val idHint = if (debugInfo["omrIdNotFilled"] == true) {
                    "OMR ID not filled in"
                } else {
                    "OMR ID unclear"
                }
                pipelineStages.add("✗ OMR ID Read — $idHint (continuing to answers)")
            }

            // Step 11: Detect answers even when OMR ID failed — blank vs marked still matters.
            stageOk("Bubble Detection Started")
            val bubbleStartMs = System.currentTimeMillis()
            val answersResult = detectAnswersWithLayout(
                thresholdMat, warpedMat, totalQuestions, layout, fillThreshold, debugInfo,
            )
            debugInfo["bubbleMs"] = System.currentTimeMillis() - bubbleStartMs
            debugInfo["answersDetected"] = answersResult.first.size
            debugInfo["answersConfidence"] = answersResult.second
            val blankCount = (totalQuestions - answersResult.first.size).coerceAtLeast(0)
            debugInfo["blankAnswersCount"] = blankCount
            stageOk("Answers Extracted (${answersResult.first.size}/$totalQuestions, blank=$blankCount)")

            attachDebugOverlay(warpedMat, layout, answersResult.first, fillThreshold, debugInfo)

            if (omrIdResult == null) {
                val idErrorMessage = if (debugInfo["omrIdNotFilled"] == true) {
                    "OMR ID not filled in. Bubble the 4-digit ID with a dark pencil, or type it below."
                } else {
                    "Could not read OMR ID clearly. Darken the ID bubbles or type the 4-digit ID below."
                }
                debugInfo["pipelineStages"] = pipelineStages.toList()
                debugInfo["processingTimeMs"] = System.currentTimeMillis() - startTime
                return ProcessingResult(
                    success = false,
                    omrId = null,
                    answers = answersResult.first,
                    confidence = answersResult.second * 0.5,
                    qrData = qrData,
                    errorMessage = idErrorMessage,
                    debugInfo = debugInfo,
                )
            }

            // Never silently return a "success" when the grid clearly missed the bubbles.
            // A deliberately blank sheet (OMR ID only) must still succeed with empty answers.
            val answered = answersResult.first.size
            val noSelections = (debugInfo["noSelectionsLayout"] as? Number)?.toInt() ?: 0
            val yield = if (totalQuestions > 0) answered.toDouble() / totalQuestions else 0.0
            val rowMarkScore = (debugInfo["rowMarkValidation"] as? Number)?.toDouble()
            val templateMismatch = debugInfo["templateMismatchWarning"] == true
            val geometryWeak = timingMarkScore < 0.55 ||
                (rowMarkScore != null && rowMarkScore < 0.55) ||
                templateMismatch
            val sparseAndEmptyLooking =
                yield < MIN_ANSWER_YIELD && noSelections >= (totalQuestions * 0.7).toInt()
            if (answered == 0 && geometryWeak) {
                debugInfo["failureReason"] = "GRID_MISALIGNED"
                return stageFail(
                    "Answers Extracted",
                    "Sheet was found but answer bubbles could not be read ($answered of $totalQuestions). " +
                        "Hold the sheet flatter, keep all timing marks in frame, and print at 100% scale.",
                )
            }
            if (sparseAndEmptyLooking && geometryWeak) {
                debugInfo["failureReason"] = "GRID_MISALIGNED"
                return stageFail(
                    "Answers Extracted",
                    "Sheet was found but answer bubbles could not be read ($answered of $totalQuestions). " +
                        "Hold the sheet flatter, keep all timing marks in frame, and print at 100% scale.",
                )
            }
            
            // Step 12: Calculate overall confidence
            val layoutConfirmed = sessionLayout != null || qrData != null
            val confidence = calculateOverallConfidence(
                timingMarkScore = timingMarkScore,
                calibrationSuccess = calibration.isCalibrated,
                omrIdConfidence = omrIdResult.confidence,
                answersConfidence = answersResult.second,
                qrDetected = layoutConfirmed,
                debugInfo = debugInfo
            )
            
            val processingTimeMs = System.currentTimeMillis() - startTime
            debugInfo["processingTimeMs"] = processingTimeMs
            debugInfo["pipelineStages"] = pipelineStages.toList()
            stageOk("Results Returned (${processingTimeMs}ms, conf=${String.format("%.2f", confidence)})")
            Log.d(TAG, "Processing completed in ${processingTimeMs}ms")
            
            return ProcessingResult(
                success = true,
                omrId = omrIdResult.id,
                answers = answersResult.first,
                confidence = confidence,
                qrData = qrData,
                errorMessage = null,
                debugInfo = debugInfo
            )
            
        } catch (e: OutOfMemoryError) {
            Log.e(TAG, "Out of memory during processing", e)
            System.gc()  // Try to recover
            debugInfo["pipelineStages"] = pipelineStages.toList()
            debugInfo["failureReason"] = "OUT_OF_MEMORY"
            return errorResult("Device ran out of memory. Please close other apps and try again.", debugInfo)
        } catch (e: Exception) {
            Log.e(TAG, "Processing error: ${e.message}", e)
            debugInfo["pipelineStages"] = pipelineStages.toList()
            debugInfo["failureReason"] = "ENGINE_ERROR"
            debugInfo["exceptionClass"] = e.javaClass.simpleName
            return errorResult("Processing error: ${e.message}", debugInfo)
        } finally {
            // Guaranteed cleanup
            bitmap?.recycle()
            originalMat?.release()
            grayMat?.release()
            warpedMat?.release()
            thresholdMat?.release()
        }
    }

    /**
     * Quick document detection for continuous scan mode.
     * This runs a lighter version of the full pipeline: decode, quality check,
     * and corner detection only.
     */
    fun detectSheet(imageBytes: ByteArray): QuickSheetDetectionResult {
        if (!checkMemoryAvailable(30)) {
            return QuickSheetDetectionResult(
                sheetDetected = false,
                isAligned = false,
                hasGoodLighting = false,
                confidence = 0.0,
                hint = "Low memory - close background apps"
            )
        }

        var bitmap: Bitmap? = null
        var rgbaMat: Mat? = null
        var grayMat: Mat? = null

        try {
            bitmap = decodeBitmapForAnalysis(imageBytes, 1200)
                ?: return QuickSheetDetectionResult(
                    sheetDetected = false,
                    isAligned = false,
                    hasGoodLighting = false,
                    confidence = 0.0,
                    hint = "Invalid image"
                )

            rgbaMat = Mat()
            Utils.bitmapToMat(bitmap, rgbaMat)
            grayMat = Mat()
            Imgproc.cvtColor(rgbaMat, grayMat, Imgproc.COLOR_RGBA2GRAY)

            val imageQuality = assessImageQuality(grayMat)
            val hasGoodLighting = imageQuality.brightnessScore in 55.0..235.0 &&
                imageQuality.contrastScore >= 0.15

            val debugInfo = mutableMapOf<String, Any>()
            val corners = detectCornerMarkersAdaptive(
                grayMat,
                determineProcessingQuality(),
                debugInfo
            )

            if (corners == null || !corners.isValid()) {
                val failureReason = classifyCornerFailure(imageQuality, debugInfo)
                val confidence = (
                    normalizedBrightness(imageQuality.brightnessScore) * 0.35 +
                        imageQuality.contrastScore.coerceIn(0.0, 1.0) * 0.25 +
                        normalizeSharpness(imageQuality.blurScore) * 0.40
                    ).coerceIn(0.0, 0.55)

                return QuickSheetDetectionResult(
                    sheetDetected = false,
                    isAligned = false,
                    hasGoodLighting = hasGoodLighting,
                    confidence = confidence,
                    hint = buildPreCaptureHint(imageQuality, failureReason)
                )
            }

            val alignmentScore = calculateSheetAlignmentScore(
                corners,
                grayMat.cols().toDouble(),
                grayMat.rows().toDouble()
            )
            val isAligned = alignmentScore >= 0.60

            val confidence = (
                0.45 +
                    normalizedBrightness(imageQuality.brightnessScore) * 0.15 +
                    imageQuality.contrastScore.coerceIn(0.0, 1.0) * 0.15 +
                    normalizeSharpness(imageQuality.blurScore) * 0.15 +
                    alignmentScore * 0.10
                ).coerceIn(0.0, 1.0)

            val hint = when {
                !hasGoodLighting -> buildPreCaptureHint(imageQuality)
                !isAligned -> "Align sheet edges"
                else -> null
            }

            return QuickSheetDetectionResult(
                sheetDetected = true,
                isAligned = isAligned,
                hasGoodLighting = hasGoodLighting,
                confidence = confidence,
                hint = hint
            )
        } catch (e: Exception) {
            Log.e(TAG, "Quick sheet detection failed: ${e.message}", e)
            return QuickSheetDetectionResult(
                sheetDetected = false,
                isAligned = false,
                hasGoodLighting = true,
                confidence = 0.0,
                hint = "Position sheet in frame"
            )
        } finally {
            bitmap?.recycle()
            rgbaMat?.release()
            grayMat?.release()
        }
    }

    /**
     * Real-time image quality analysis for the scanner overlay.
     * Returns normalized values expected by the Flutter UI (0.0-1.0).
     */
    fun analyzeImageQuality(imageBytes: ByteArray): Map<String, Double> {
        if (!checkMemoryAvailable(20)) {
            return mapOf(
                "brightness" to 0.5,
                "contrast" to 0.3,
                "sharpness" to 0.2
            )
        }

        var bitmap: Bitmap? = null
        var rgbaMat: Mat? = null
        var grayMat: Mat? = null

        try {
            bitmap = decodeBitmapForAnalysis(imageBytes, 1000)
                ?: return mapOf(
                    "brightness" to 0.5,
                    "contrast" to 0.3,
                    "sharpness" to 0.2
                )

            rgbaMat = Mat()
            Utils.bitmapToMat(bitmap, rgbaMat)
            grayMat = Mat()
            Imgproc.cvtColor(rgbaMat, grayMat, Imgproc.COLOR_RGBA2GRAY)

            val quality = assessImageQuality(grayMat)
            return mapOf(
                "brightness" to normalizedBrightness(quality.brightnessScore),
                "contrast" to quality.contrastScore.coerceIn(0.0, 1.0),
                "sharpness" to normalizeSharpness(quality.blurScore)
            )
        } catch (e: Exception) {
            Log.e(TAG, "Image quality analysis failed: ${e.message}", e)
            return mapOf(
                "brightness" to 0.5,
                "contrast" to 0.3,
                "sharpness" to 0.2
            )
        } finally {
            bitmap?.recycle()
            rgbaMat?.release()
            grayMat?.release()
        }
    }
    
    private fun errorResult(message: String, debugInfo: Map<String, Any>): ProcessingResult {
        return ProcessingResult(
            success = false,
            omrId = null,
            answers = emptyMap(),
            confidence = 0.0,
            qrData = null,
            errorMessage = message,
            debugInfo = debugInfo
        )
    }
    
    private fun cleanup(vararg mats: Mat) {
        mats.forEach { it.release() }
    }

    private fun decodeBitmapForAnalysis(imageBytes: ByteArray, maxDimension: Int): Bitmap? {
        if (imageBytes.isEmpty() || imageBytes.size > MAX_IMAGE_SIZE_BYTES) {
            return null
        }

        val bounds = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            return null
        }

        val maxDim = maxOf(bounds.outWidth, bounds.outHeight)
        var sampleSize = 1
        // Decode near the target size — avoid loading a full 12MP bitmap then shrinking.
        while (maxDim / sampleSize > maxDimension) {
            sampleSize *= 2
        }

        val decodeOptions = BitmapFactory.Options().apply {
            inJustDecodeBounds = false
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.RGB_565
            inDither = true
        }

        Log.d(
            TAG,
            "Decode ${bounds.outWidth}x${bounds.outHeight} sample=$sampleSize targetMax=$maxDimension",
        )

        val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size, decodeOptions)
            ?: return null

        val oriented = applyExifOrientation(bitmap, imageBytes)
        return downscaleIfNeeded(oriented, maxDimension)
    }

    /**
     * Camera JPEGs often store sensor orientation in EXIF. BitmapFactory ignores it,
     * which breaks corner/timing-mark detection when preview and pixels disagree.
     */
    private fun applyExifOrientation(bitmap: Bitmap, imageBytes: ByteArray): Bitmap {
        val orientation = try {
            ExifInterface(ByteArrayInputStream(imageBytes)).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        } catch (error: Exception) {
            Log.w(TAG, "EXIF read failed: ${error.message}")
            ExifInterface.ORIENTATION_NORMAL
        }

        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.preScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.preScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.preScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f)
                matrix.preScale(-1f, 1f)
            }
            else -> return bitmap
        }

        return try {
            val rotated = Bitmap.createBitmap(
                bitmap,
                0,
                0,
                bitmap.width,
                bitmap.height,
                matrix,
                true,
            )
            if (rotated != bitmap) {
                bitmap.recycle()
            }
            rotated
        } catch (error: Exception) {
            Log.w(TAG, "EXIF rotation failed: ${error.message}")
            bitmap
        }
    }

    private fun normalizedBrightness(brightnessScore: Double): Double {
        return (brightnessScore / 255.0).coerceIn(0.0, 1.0)
    }

    private fun normalizeSharpness(blurScore: Double): Double {
        // Map the OpenCV Laplacian variance to the 0-1 UI scale used by Flutter.
        return (blurScore / (MIN_BLUR_THRESHOLD * 2.0)).coerceIn(0.0, 1.0)
    }

    private fun buildPreCaptureHint(quality: ImageQuality, failureReason: String? = null): String {
        return when (failureReason) {
            "NO_SHEET" -> "No answer sheet detected"
            "CORNERS_INCOMPLETE" -> "Show all four corner squares"
            "TOO_BLURRY" -> "Hold steady — image blurry"
            "TOO_DARK" -> "Too dark — tap Light or add a lamp"
            "TOO_BRIGHT" -> "Reduce glare"
            "LOW_CONTRAST" -> "Improve sheet contrast"
            "NOISY_IMAGE" -> "Clean lens and retry"
            else -> when {
                quality.brightnessScore < 60 -> "Improve lighting"
                quality.brightnessScore > 230 -> "Reduce glare"
                quality.blurScore < MIN_BLUR_THRESHOLD * 0.6 -> "Hold steady"
                quality.contrastScore < 0.15 -> "Improve sheet contrast"
                else -> "Position answer sheet in frame"
            }
        }
    }

    /**
     * Classify why corner detection failed so Flutter can show a specific message.
     */
    private fun classifyCornerFailure(
        quality: ImageQuality,
        debugInfo: MutableMap<String, Any>
    ): String {
        if (quality.blurScore < MIN_BLUR_THRESHOLD * 0.3) return "TOO_BLURRY"
        if (quality.brightnessScore < 50) return "TOO_DARK"
        if (quality.brightnessScore > 230) return "TOO_BRIGHT"
        if (quality.contrastScore < 0.15) return "LOW_CONTRAST"
        if (quality.noiseScore > NOISE_THRESHOLD * 2) return "NOISY_IMAGE"

        val missing = debugInfo["missingQuadrants"]
        if (missing is List<*> && missing.isNotEmpty()) return "CORNERS_INCOMPLETE"

        val candidates = (debugInfo["balancedCandidates"] as? Number)?.toInt() ?: 0
        val cornerVia = debugInfo["cornerDetectionSucceededVia"]?.toString()
        if (candidates < 2 && cornerVia == "none") return "NO_SHEET"

        return "CORNERS_INCOMPLETE"
    }

    /**
     * Build a helpful error message based on image quality and detection context.
     */
    private fun buildCornerDetectionErrorMessage(
        quality: ImageQuality,
        debugInfo: MutableMap<String, Any>,
        failureReason: String
    ): String {
        return when (failureReason) {
            "NO_SHEET" ->
                "No answer sheet detected. Point the camera at a printed OMR page with all four black corner squares visible."
            "CORNERS_INCOMPLETE" ->
                "Corner markers not fully visible. Move back so the entire sheet fits in the frame, including all four corner squares."
            "TOO_BLURRY" ->
                "Image is too blurry. Hold your phone steady and tap to focus before capturing."
            "TOO_DARK" ->
                "Image is too dark. Move to a brighter area or turn on a light."
            "TOO_BRIGHT" ->
                "Image is overexposed. Reduce lighting or avoid direct light on the sheet."
            "LOW_CONTRAST" ->
                "Cannot distinguish the sheet from the background. Lay the paper flat with even lighting."
            "NOISY_IMAGE" ->
                "Image is very noisy. Clean your camera lens and ensure good lighting."
            else ->
                "Could not detect all 4 corner markers. Ensure the entire sheet is visible with good lighting."
        }
    }

    private fun buildTimingMarkErrorMessage(
        timingMarkScore: Double,
        debugInfo: MutableMap<String, Any>
    ): String {
        val found = debugInfo["timingMarksFound"]
        val expected = debugInfo["timingMarksExpected"]
        val pct = (timingMarkScore * 100).toInt()
        return if (found is Number && expected is Number && expected.toInt() > 0) {
            "Timing marks not clear enough ($pct% — ${found.toInt()} of ${expected.toInt()}). " +
                "Align the sheet edges with the green tick guides and keep the page flat."
        } else {
            "Timing marks not clear enough ($pct%). " +
                "Align the sheet edges with the green tick guides. Re-print at 100% scale if the sheet was shrunk."
        }
    }

    private fun calculateSheetAlignmentScore(
        corners: DetectedCorners,
        imageWidth: Double,
        imageHeight: Double
    ): Double {
        val topTilt = 1.0 - (abs(corners.topLeft.y - corners.topRight.y) / imageHeight).coerceIn(0.0, 1.0)
        val bottomTilt = 1.0 - (abs(corners.bottomLeft.y - corners.bottomRight.y) / imageHeight).coerceIn(0.0, 1.0)
        val leftTilt = 1.0 - (abs(corners.topLeft.x - corners.bottomLeft.x) / imageWidth).coerceIn(0.0, 1.0)
        val rightTilt = 1.0 - (abs(corners.topRight.x - corners.bottomRight.x) / imageWidth).coerceIn(0.0, 1.0)

        val minX = minOf(corners.topLeft.x, corners.bottomLeft.x)
        val maxX = maxOf(corners.topRight.x, corners.bottomRight.x)
        val minY = minOf(corners.topLeft.y, corners.topRight.y)
        val maxY = maxOf(corners.bottomLeft.y, corners.bottomRight.y)

        val widthCoverage = ((maxX - minX) / imageWidth).coerceIn(0.0, 1.0)
        val heightCoverage = ((maxY - minY) / imageHeight).coerceIn(0.0, 1.0)
        val coverageScore = ((widthCoverage + heightCoverage) / 2.0).coerceIn(0.0, 1.0)

        return ((topTilt + bottomTilt + leftTilt + rightTilt) / 4.0 * 0.65 +
            coverageScore * 0.35).coerceIn(0.0, 1.0)
    }
    
    /**
     * Assess image quality to handle low-quality cameras
     * Checks blur, contrast, brightness, and noise levels
     */
    private fun assessImageQuality(grayMat: Mat): ImageQuality {
        val issues = mutableListOf<String>()
        
        // 1. Blur detection using Laplacian variance
        // Higher variance = sharper image
        val laplacian = Mat()
        Imgproc.Laplacian(grayMat, laplacian, CvType.CV_64F)
        val mean = MatOfDouble()
        val stdDev = MatOfDouble()
        Core.meanStdDev(laplacian, mean, stdDev)
        val blurScore = stdDev.get(0, 0)[0].pow(2)  // Variance
        laplacian.release()
        mean.release()
        stdDev.release()
        
        if (blurScore < MIN_BLUR_THRESHOLD) {
            issues.add("Image is blurry - hold phone steady")
        }
        
        // 2. Contrast analysis
        val minMax = Core.minMaxLoc(grayMat)
        val minVal = minMax.minVal
        val maxVal = minMax.maxVal
        val contrastRatio = if (minVal > 0) maxVal / minVal else maxVal / 1.0
        val contrastScore = (maxVal - minVal) / 255.0  // Normalized 0-1
        
        if (contrastRatio < MIN_CONTRAST_RATIO || contrastScore < 0.3) {
            issues.add("Low contrast - ensure good lighting")
        }
        
        // 3. Brightness analysis
        val meanBrightness = Core.mean(grayMat).`val`[0]
        
        if (meanBrightness < 60) {
            issues.add("Image too dark - add more light")
        } else if (meanBrightness > 220) {
            issues.add("Image overexposed - reduce light or glare")
        }
        
        // 4. Noise estimation using local variance
        val blurred = Mat()
        Imgproc.GaussianBlur(grayMat, blurred, Size(5.0, 5.0), 0.0)
        val diff = Mat()
        Core.absdiff(grayMat, blurred, diff)
        val noiseMean = Core.mean(diff).`val`[0]
        blurred.release()
        diff.release()
        
        if (noiseMean > NOISE_THRESHOLD) {
            issues.add("Image is noisy - clean camera lens")
        }
        
        // Image is acceptable if there are no critical issues
        // Allow some issues but fail if blur is too severe
        val isAcceptable = blurScore >= MIN_BLUR_THRESHOLD * 0.5 && 
                           contrastScore >= 0.2 &&
                           meanBrightness in 30.0..240.0
        
        return ImageQuality(
            isAcceptable = isAcceptable,
            blurScore = blurScore,
            contrastScore = contrastScore,
            brightnessScore = meanBrightness,
            noiseScore = noiseMean,
            issues = issues
        )
    }
    
    /**
     * Enhance image for low-quality cameras
     * Applies adaptive techniques based on detected issues
     */
    private fun enhanceImageForLowQualityCamera(grayMat: Mat, quality: ImageQuality) {
        val veryDark = quality.brightnessScore < 55.0
        val dark = quality.brightnessScore < DARK_CAPTURE_BRIGHTNESS

        // 1. CLAHE for low contrast or dark captures
        if (quality.contrastScore < 0.4 || dark) {
            Log.d(TAG, "Applying CLAHE for contrast enhancement")
            val clipLimit = if (veryDark) 2.5 else 2.0
            val clahe = Imgproc.createCLAHE(clipLimit, Size(8.0, 8.0))
            clahe.apply(grayMat, grayMat)
        }
        
        // 2. Adjust brightness if too dark or too bright
        if (veryDark) {
            val alpha = 1.45
            val beta = 65.0
            grayMat.convertTo(grayMat, -1, alpha, beta)
            Log.d(TAG, "Applied strong brightness correction (very dark image)")
        } else if (dark) {
            val alpha = 1.28
            val beta = 48.0
            grayMat.convertTo(grayMat, -1, alpha, beta)
            Log.d(TAG, "Applied brightness correction (dark image)")
        } else if (quality.brightnessScore > 200) {
            // Image is too bright - reduce
            val alpha = 0.9
            val beta = -20.0
            grayMat.convertTo(grayMat, -1, alpha, beta)
            Log.d(TAG, "Applied brightness correction (bright image)")
        }
        
        // 3. Denoise if image is noisy (but skip if memory constrained)
        if (quality.noiseScore > NOISE_THRESHOLD) {
            try {
                // Use simple median blur for denoising (faster than fastNlMeansDenoising)
                Imgproc.medianBlur(grayMat, grayMat, 3)
                Log.d(TAG, "Applied median blur for noise reduction")
            } catch (e: Exception) {
                Log.w(TAG, "Denoising failed: ${e.message}")
            }
        }
        
        // 4. Sharpen slightly if blurry (only if not too noisy)
        if (quality.blurScore < MIN_BLUR_THRESHOLD && quality.noiseScore < NOISE_THRESHOLD) {
            val kernel = Mat(3, 3, CvType.CV_32F)
            kernel.put(0, 0, 
                0.0, -0.5, 0.0,
                -0.5, 3.0, -0.5,
                0.0, -0.5, 0.0
            )
            Imgproc.filter2D(grayMat, grayMat, -1, kernel)
            kernel.release()
            Log.d(TAG, "Applied unsharp mask for sharpening")
        }
    }
    
    /**
     * Build a helpful error message based on image quality issues (legacy callers).
     */
    private fun buildCornerDetectionErrorMessage(quality: ImageQuality): String {
        return buildCornerDetectionErrorMessage(quality, mutableMapOf(), classifyCornerFailure(quality, mutableMapOf()))
    }
    
    /**
     * Adaptive corner detection - chooses method based on processing quality
     */
    private fun detectCornerMarkersAdaptive(grayMat: Mat, quality: ProcessingQuality, 
                                            debugInfo: MutableMap<String, Any>): DetectedCorners? {
        val width = grayMat.cols().toDouble()
        val height = grayMat.rows().toDouble()
        
        // Try primary method based on quality
        var corners = when (quality) {
            ProcessingQuality.FAST -> {
                debugInfo["cornerMethod"] = "fast_fallback"
                detectCornerMarkersFallback(grayMat, width, height, debugInfo)
            }
            ProcessingQuality.BALANCED -> {
                debugInfo["cornerMethod"] = "balanced"
                detectCornerMarkersBalanced(grayMat, debugInfo)
            }
            ProcessingQuality.HIGH -> {
                debugInfo["cornerMethod"] = "advanced"
                detectCornerMarkersAdvanced(grayMat, debugInfo)
            }
        }
        
        if (corners != null && corners.isValid()) {
            debugInfo["cornerDetectionSucceededVia"] = debugInfo["cornerMethod"] ?: "primary"
            return corners
        }
        
        // If primary method failed, try multi-threshold approach (good for low-quality cameras)
        Log.d(TAG, "Primary corner detection failed, trying multi-threshold approach")
        debugInfo["usingMultiThreshold"] = true
        corners = detectCornersMultiThreshold(grayMat, width, height, debugInfo)
        if (corners != null && corners.isValid()) {
            debugInfo["cornerDetectionSucceededVia"] = "multiThreshold"
            return corners
        }
        
        // Last resort: edge-based detection
        Log.d(TAG, "Multi-threshold failed, trying edge-based detection")
        debugInfo["usingEdgeDetection"] = true
        corners = detectCornersEdgeBased(grayMat, width, height, debugInfo)
        if (corners != null && corners.isValid()) {
            debugInfo["cornerDetectionSucceededVia"] = "edge"
            return corners
        }
        
        debugInfo["cornerDetectionSucceededVia"] = "none"
        return corners
    }
    
    /**
     * Multi-threshold corner detection - tries multiple threshold values
     * Especially useful for low-contrast/poor lighting conditions
     */
    private fun detectCornersMultiThreshold(grayMat: Mat, width: Double, height: Double,
                                             debugInfo: MutableMap<String, Any>): DetectedCorners? {
        // Try multiple fixed threshold values
        val thresholds = listOf(60.0, 70.0, 80.0, 100.0, 120.0, 140.0, 160.0)
        
        for (threshold in thresholds) {
            val binaryMat = Mat()
            Imgproc.threshold(grayMat, binaryMat, threshold, 255.0, Imgproc.THRESH_BINARY_INV)
            
            // Optional: morphological closing to fill gaps
            val kernel = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(3.0, 3.0))
            Imgproc.morphologyEx(binaryMat, binaryMat, Imgproc.MORPH_CLOSE, kernel)
            kernel.release()
            
            val contours = mutableListOf<MatOfPoint>()
            val hierarchy = Mat()
            Imgproc.findContours(binaryMat, contours, hierarchy, Imgproc.RETR_EXTERNAL, Imgproc.CHAIN_APPROX_SIMPLE)
            
            val candidates = mutableListOf<Point>()
            val expectedArea = (width * CORNER_MARKER_SIZE / OUTPUT_WIDTH) * (height * CORNER_MARKER_SIZE / OUTPUT_HEIGHT)
            
            for (contour in contours) {
                val area = Imgproc.contourArea(contour)
                // More relaxed area filter for low-quality images
                if (area < expectedArea * 0.2 || area > expectedArea * 6) continue
                
                val rect = Imgproc.boundingRect(contour)
                val aspectRatio = rect.width.toDouble() / rect.height.toDouble()
                // More relaxed aspect ratio for distorted images
                if (aspectRatio < 0.5 || aspectRatio > 2.0) continue
                
                candidates.add(Point(rect.x + rect.width / 2.0, rect.y + rect.height / 2.0))
            }
            
            binaryMat.release()
            hierarchy.release()
            
            if (candidates.size >= 4) {
                val corners = assignCornersFromCandidates(candidates, width, height, debugInfo)
                if (corners != null && corners.isValid()) {
                    debugInfo["multiThresholdValue"] = threshold
                    Log.d(TAG, "Multi-threshold succeeded at threshold=$threshold")
                    return corners
                }
            }
        }
        
        return null
    }
    
    /**
     * Edge-based corner detection using Canny edges
     * Good fallback for very low contrast or unusual lighting
     */
    private fun detectCornersEdgeBased(grayMat: Mat, width: Double, height: Double,
                                        debugInfo: MutableMap<String, Any>): DetectedCorners? {
        // Apply Canny edge detection
        val edges = Mat()
        Imgproc.Canny(grayMat, edges, 50.0, 150.0)
        
        // Dilate edges to connect broken lines
        val kernel = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(3.0, 3.0))
        Imgproc.dilate(edges, edges, kernel)
        kernel.release()
        
        val contours = mutableListOf<MatOfPoint>()
        val hierarchy = Mat()
        Imgproc.findContours(edges, contours, hierarchy, Imgproc.RETR_EXTERNAL, Imgproc.CHAIN_APPROX_SIMPLE)
        
        val candidates = mutableListOf<Pair<Point, Double>>()  // center, area
        val expectedArea = (width * CORNER_MARKER_SIZE / OUTPUT_WIDTH) * (height * CORNER_MARKER_SIZE / OUTPUT_HEIGHT)
        
        for (contour in contours) {
            val area = Imgproc.contourArea(contour)
            if (area < expectedArea * 0.1 || area > expectedArea * 8) continue
            
            val rect = Imgproc.boundingRect(contour)
            val aspectRatio = rect.width.toDouble() / rect.height.toDouble()
            if (aspectRatio < 0.4 || aspectRatio > 2.5) continue
            
            // Score based on squareness
            val squarenessScore = 1.0 - abs(aspectRatio - 1.0)
            if (squarenessScore > 0.3) {
                candidates.add(Pair(
                    Point(rect.x + rect.width / 2.0, rect.y + rect.height / 2.0),
                    area * squarenessScore
                ))
            }
        }
        
        edges.release()
        hierarchy.release()
        
        // Sort by score and take best candidates
        val sortedCandidates = candidates.sortedByDescending { it.second }
        
        if (sortedCandidates.size >= 4) {
            val corners = assignCornersFromCandidates(
                sortedCandidates.take(8).map { it.first },  // Take top 8 candidates
                width, height, debugInfo
            )
            if (corners != null && corners.isValid()) {
                Log.d(TAG, "Edge-based detection succeeded")
                return corners
            }
        }
        
        return null
    }
    
    /**
     * Balanced corner detection - simpler than advanced, faster than full processing
     */
    private fun detectCornerMarkersBalanced(grayMat: Mat, debugInfo: MutableMap<String, Any>): DetectedCorners? {
        val width = grayMat.cols().toDouble()
        val height = grayMat.rows().toDouble()
        
        // Gentle blur to suppress sensor noise before binarizing.
        val blurredMat = Mat()
        Imgproc.GaussianBlur(grayMat, blurredMat, Size(5.0, 5.0), 0.0)
        
        // Adaptive threshold handles uneven desk lighting / shadow / glare far better
        // than a single global Otsu cutoff (the most lighting-sensitive step before).
        val binaryMat = Mat()
        val block = adaptiveBlockSize(width, height)
        debugInfo["cornerAdaptiveBlock"] = block
        Imgproc.adaptiveThreshold(
            blurredMat, binaryMat,
            255.0,
            Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C,
            Imgproc.THRESH_BINARY_INV,
            block, 8.0
        )
        // Solidify the black marker squares (adaptive can leave hollow edges).
        val kernel = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(3.0, 3.0))
        Imgproc.morphologyEx(binaryMat, binaryMat, Imgproc.MORPH_CLOSE, kernel)
        kernel.release()
        
        var markerCandidates = collectCornerCandidates(binaryMat, width, height, debugInfo)
        
        // If adaptive under-detects (e.g. very flat, uniform lighting), retry once
        // with Otsu so we never regress versus the old behavior.
        if (markerCandidates.size < 4) {
            debugInfo["balancedOtsuRetry"] = true
            Imgproc.threshold(blurredMat, binaryMat, 0.0, 255.0, Imgproc.THRESH_BINARY_INV + Imgproc.THRESH_OTSU)
            markerCandidates = collectCornerCandidates(binaryMat, width, height, debugInfo)
        }
        
        blurredMat.release()
        binaryMat.release()
        
        debugInfo["balancedCandidates"] = markerCandidates.size
        
        if (markerCandidates.size < 4) {
            return null
        }
        
        return assignCornersFromCandidates(markerCandidates, width, height, debugInfo)
    }
    
    /** Odd adaptive-threshold block size scaled to the working image. */
    private fun adaptiveBlockSize(width: Double, height: Double): Int {
        val approx = (minOf(width, height) / 25.0).toInt()
        val odd = if (approx % 2 == 0) approx + 1 else approx
        return odd.coerceIn(11, 51)
    }
    
    /**
     * Find corner-marker candidates in a binary image using loosened area/aspect
     * tolerances. Records per-reason rejection counts in debugInfo so a single scan
     * is diagnosable without adb logcat.
     */
    private fun collectCornerCandidates(binaryMat: Mat, width: Double, height: Double,
                                        debugInfo: MutableMap<String, Any>): List<Point> {
        val contours = mutableListOf<MatOfPoint>()
        val hierarchy = Mat()
        Imgproc.findContours(binaryMat, contours, hierarchy, Imgproc.RETR_EXTERNAL, Imgproc.CHAIN_APPROX_SIMPLE)
        
        val candidates = mutableListOf<Point>()
        val expectedArea = (width * CORNER_MARKER_SIZE / OUTPUT_WIDTH) * (height * CORNER_MARKER_SIZE / OUTPUT_HEIGHT)
        
        var rejectAreaLow = 0
        var rejectAreaHigh = 0
        var rejectAspect = 0
        
        for (contour in contours) {
            val area = Imgproc.contourArea(contour)
            // Loosened area window: sheets that don't fill the frame make markers much
            // smaller than the full-frame estimate; perspective skew makes them larger.
            if (area < expectedArea * 0.12) { rejectAreaLow++; continue }
            if (area > expectedArea * 8.0) { rejectAreaHigh++; continue }
            
            val rect = Imgproc.boundingRect(contour)
            val aspectRatio = rect.width.toDouble() / rect.height.toDouble()
            // Loosened aspect window: skew squashes squares into rectangles.
            if (aspectRatio < 0.55 || aspectRatio > 1.8) { rejectAspect++; continue }
            
            candidates.add(Point(rect.x + rect.width / 2.0, rect.y + rect.height / 2.0))
        }
        
        hierarchy.release()
        
        debugInfo["contourCount"] = contours.size
        debugInfo["rejectAreaLow"] = rejectAreaLow
        debugInfo["rejectAreaHigh"] = rejectAreaHigh
        debugInfo["rejectAspect"] = rejectAspect
        debugInfo["expectedMarkerArea"] = expectedArea
        
        return candidates
    }
    
    /**
     * Advanced corner detection using the specific pattern:
     * Black square with white center (concentric squares)
     */
    private fun detectCornerMarkersAdvanced(grayMat: Mat, debugInfo: MutableMap<String, Any>): DetectedCorners? {
        val width = grayMat.cols().toDouble()
        val height = grayMat.rows().toDouble()
        
        // Apply bilateral filter to reduce noise while keeping edges sharp
        val filteredMat = Mat()
        Imgproc.bilateralFilter(grayMat, filteredMat, 9, 75.0, 75.0)
        
        // Apply Otsu threshold
        val binaryMat = Mat()
        Imgproc.threshold(filteredMat, binaryMat, 0.0, 255.0, Imgproc.THRESH_BINARY_INV + Imgproc.THRESH_OTSU)
        
        // Find contours with hierarchy (needed to find nested contours)
        val contours = mutableListOf<MatOfPoint>()
        val hierarchy = Mat()
        Imgproc.findContours(binaryMat, contours, hierarchy, Imgproc.RETR_TREE, Imgproc.CHAIN_APPROX_SIMPLE)
        
        debugInfo["totalContours"] = contours.size
        
        // Find contours that have a child contour (black square with white center)
        val markerCandidates = mutableListOf<Pair<Point, Double>>()  // center, area
        
        for (i in contours.indices) {
            val contour = contours[i]
            val area = Imgproc.contourArea(contour)
            
            // Expected marker area based on image size
            val expectedArea = (width * CORNER_MARKER_SIZE / OUTPUT_WIDTH) * (height * CORNER_MARKER_SIZE / OUTPUT_HEIGHT)
            if (area < expectedArea * 0.2 || area > expectedArea * 5) continue
            
            // Check aspect ratio (should be square)
            val rect = Imgproc.boundingRect(contour)
            val aspectRatio = rect.width.toDouble() / rect.height.toDouble()
            if (aspectRatio < 0.7 || aspectRatio > 1.4) continue
            
            // Check if this contour has a child (the white center)
            val hierarchyRow = hierarchy.get(0, i)
            if (hierarchyRow != null && hierarchyRow.size >= 4) {
                val firstChild = hierarchyRow[2].toInt()
                if (firstChild >= 0) {
                    // This contour has a child - likely our marker pattern
                    val childContour = contours[firstChild]
                    val childArea = Imgproc.contourArea(childContour)
                    
                    // Child should be roughly 25% of parent (50% width/height = 25% area)
                    val areaRatio = childArea / area
                    if (areaRatio > 0.15 && areaRatio < 0.4) {
                        val center = Point(
                            rect.x + rect.width / 2.0,
                            rect.y + rect.height / 2.0
                        )
                        markerCandidates.add(Pair(center, area))
                    }
                }
            }
        }
        
        debugInfo["markerCandidates"] = markerCandidates.size
        Log.d(TAG, "Found ${markerCandidates.size} marker candidates with nested pattern")
        
        filteredMat.release()
        binaryMat.release()
        hierarchy.release()
        
        if (markerCandidates.size < 4) {
            // Fallback to simpler detection
            return detectCornerMarkersFallback(grayMat, width, height, debugInfo)
        }
        
        // Assign candidates to corners
        return assignCornersFromCandidates(markerCandidates.map { it.first }, width, height, debugInfo)
    }
    
    /**
     * Fallback corner detection using dark region analysis
     */
    private fun detectCornerMarkersFallback(grayMat: Mat, width: Double, height: Double, 
                                             debugInfo: MutableMap<String, Any>): DetectedCorners? {
        debugInfo["usingFallbackCornerDetection"] = true
        Log.d(TAG, "Using fallback corner detection")
        
        val searchSize = (minOf(width, height) * 0.12).toInt()
        val corners = mutableListOf<Point?>()
        
        // Search in each corner region
        val regions = listOf(
            Rect(0, 0, searchSize, searchSize),  // TL
            Rect((width - searchSize).toInt(), 0, searchSize, searchSize),  // TR
            Rect(0, (height - searchSize).toInt(), searchSize, searchSize),  // BL
            Rect((width - searchSize).toInt(), (height - searchSize).toInt(), searchSize, searchSize)  // BR
        )
        
        val offsets = listOf(
            Point(0.0, 0.0),
            Point(width - searchSize, 0.0),
            Point(0.0, height - searchSize),
            Point(width - searchSize, height - searchSize)
        )
        
        for ((idx, region) in regions.withIndex()) {
            val roi = Mat(grayMat, region)
            val corner = findCornerMarkerInRegion(roi)
            if (corner != null) {
                corners.add(Point(corner.x + offsets[idx].x, corner.y + offsets[idx].y))
            } else {
                corners.add(null)
            }
            roi.release()
        }
        
        val detectedCount = corners.count { it != null }
        debugInfo["fallbackCornersFound"] = detectedCount
        
        if (detectedCount < 4) {
            debugInfo["missingCorners"] = corners.mapIndexed { i, c -> 
                listOf("TL", "TR", "BL", "BR")[i] to (c == null)
            }.filter { it.second }.map { it.first }
            return null
        }
        
        return DetectedCorners(
            topLeft = corners[0]!!,
            topRight = corners[1]!!,
            bottomLeft = corners[2]!!,
            bottomRight = corners[3]!!
        )
    }
    
    /**
     * Find a corner marker within a small region
     */
    private fun findCornerMarkerInRegion(roi: Mat): Point? {
        // Adaptive threshold (matches the main corner pass) so a shadowed or
        // glare-hit corner ROI still binarizes the marker cleanly.
        val binary = Mat()
        val block = adaptiveBlockSize(roi.cols().toDouble(), roi.rows().toDouble())
        Imgproc.adaptiveThreshold(
            roi, binary,
            255.0,
            Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C,
            Imgproc.THRESH_BINARY_INV,
            block, 8.0
        )
        // Remove speckle noise that adaptive threshold produces on blank paper.
        val openKernel = Imgproc.getStructuringElement(Imgproc.MORPH_RECT, Size(3.0, 3.0))
        Imgproc.morphologyEx(binary, binary, Imgproc.MORPH_OPEN, openKernel)
        openKernel.release()
        
        // Find contours
        val contours = mutableListOf<MatOfPoint>()
        val hierarchy = Mat()
        Imgproc.findContours(binary, contours, hierarchy, Imgproc.RETR_EXTERNAL, Imgproc.CHAIN_APPROX_SIMPLE)
        
        var bestContour: MatOfPoint? = null
        var bestScore = 0.0
        
        for (contour in contours) {
            val area = Imgproc.contourArea(contour)
            if (area < 50) continue
            
            val rect = Imgproc.boundingRect(contour)
            val aspectRatio = rect.width.toDouble() / rect.height.toDouble()
            
            // Score based on squareness and size
            val squarenessScore = 1.0 - abs(aspectRatio - 1.0)
            val sizeScore = minOf(area / 500.0, 1.0)
            val score = squarenessScore * sizeScore
            
            if (score > bestScore) {
                bestScore = score
                bestContour = contour
            }
        }
        
        binary.release()
        hierarchy.release()
        
        if (bestContour != null && bestScore > 0.5) {
            val rect = Imgproc.boundingRect(bestContour)
            return Point(rect.x + rect.width / 2.0, rect.y + rect.height / 2.0)
        }
        
        return null
    }
    
    /**
     * Assign detected points to corner positions based on location
     */
    private fun assignCornersFromCandidates(candidates: List<Point>, width: Double, height: Double,
                                             debugInfo: MutableMap<String, Any>): DetectedCorners? {
        // Overlapping bands (0.38 / 0.62) are forgiving of off-centre framing
        // and skewed phone angles.
        val leftBand = width * 0.38
        val rightBand = width * 0.62
        val topBand = height * 0.38
        val botBand = height * 0.62
        
        val tlQuad = candidates.filter { it.x < leftBand && it.y < topBand }
        val trQuad = candidates.filter { it.x > rightBand && it.y < topBand }
        val blQuad = candidates.filter { it.x < leftBand && it.y > botBand }
        val brQuad = candidates.filter { it.x > rightBand && it.y > botBand }
        
        debugInfo["quadrantCountTL"] = tlQuad.size
        debugInfo["quadrantCountTR"] = trQuad.size
        debugInfo["quadrantCountBL"] = blQuad.size
        debugInfo["quadrantCountBR"] = brQuad.size
        
        // Prefer the best candidate inside the expected band...
        var topLeft = tlQuad.minByOrNull { it.x + it.y }
        var topRight = trQuad.minByOrNull { (width - it.x) + it.y }
        var bottomLeft = blQuad.minByOrNull { it.x + (height - it.y) }
        var bottomRight = brQuad.minByOrNull { (width - it.x) + (height - it.y) }
        
        // ...but if a band is empty (skew / partial framing), fall back to the overall
        // candidate nearest that physical corner instead of failing the whole detection.
        val usedNearestFallback = mutableListOf<String>()
        if (topLeft == null) { topLeft = candidates.minByOrNull { it.x + it.y }; usedNearestFallback.add("TL") }
        if (topRight == null) { topRight = candidates.minByOrNull { (width - it.x) + it.y }; usedNearestFallback.add("TR") }
        if (bottomLeft == null) { bottomLeft = candidates.minByOrNull { it.x + (height - it.y) }; usedNearestFallback.add("BL") }
        if (bottomRight == null) { bottomRight = candidates.minByOrNull { (width - it.x) + (height - it.y) }; usedNearestFallback.add("BR") }
        if (usedNearestFallback.isNotEmpty()) {
            debugInfo["cornerNearestFallback"] = usedNearestFallback
        }
        
        if (topLeft == null || topRight == null || bottomLeft == null || bottomRight == null) {
            debugInfo["cornerAssignmentFailed"] = true
            debugInfo["missingQuadrants"] = listOf(
                "TL" to (topLeft == null), "TR" to (topRight == null),
                "BL" to (bottomLeft == null), "BR" to (bottomRight == null)
            ).filter { it.second }.map { it.first }
            return null
        }
        
        // Guard against the nearest-fallback assigning the same point to two corners.
        val chosen = listOf(topLeft, topRight, bottomLeft, bottomRight)
        val distinctCount = chosen.distinctBy { "${it.x.toInt()},${it.y.toInt()}" }.size
        if (distinctCount < 4) {
            debugInfo["cornerAssignmentDuplicate"] = true
            return null
        }
        
        return DetectedCorners(topLeft, topRight, bottomLeft, bottomRight)
    }
    
    /**
     * Apply perspective transform to get a properly aligned image
     */
    private fun applyPerspectiveTransform(srcMat: Mat, corners: DetectedCorners): Mat {
        val markerCenterOffset = CORNER_OFFSET + (CORNER_MARKER_SIZE / 2.0)
        val srcPoints = MatOfPoint2f(
            corners.topLeft,
            corners.topRight,
            corners.bottomRight,
            corners.bottomLeft
        )
        
        val dstPoints = MatOfPoint2f(
            Point(markerCenterOffset, markerCenterOffset),
            Point(OUTPUT_WIDTH - markerCenterOffset, markerCenterOffset),
            Point(OUTPUT_WIDTH - markerCenterOffset, OUTPUT_HEIGHT - markerCenterOffset),
            Point(markerCenterOffset, OUTPUT_HEIGHT - markerCenterOffset)
        )
        
        val transformMatrix = Imgproc.getPerspectiveTransform(srcPoints, dstPoints)
        val outputMat = Mat()
        Imgproc.warpPerspective(srcMat, outputMat, transformMatrix, 
            Size(OUTPUT_WIDTH.toDouble(), OUTPUT_HEIGHT.toDouble()))
        
        transformMatrix.release()
        srcPoints.release()
        dstPoints.release()
        
        return outputMat
    }
    
    /**
     * Validate alignment by checking for timing marks along edges
     */
    private fun validateTimingMarks(warpedMat: Mat, debugInfo: MutableMap<String, Any>): Double {
        var foundMarks = 0
        var expectedMarks = 0
        
        // Adaptive threshold (same approach as bubble detection) is robust to the
        // uneven lighting that a single global Otsu cutoff mishandles at the edges.
        val binary = Mat()
        Imgproc.adaptiveThreshold(
            warpedMat, binary,
            255.0,
            Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C,
            Imgproc.THRESH_BINARY_INV,
            15, 8.0
        )
        
        // Check top edge timing marks
        var x = 60.0
        while (x < 535) {
            expectedMarks++
            if (checkTimingMark(binary, warpedMat, x, TIMING_MARK_EDGE_OFFSET)) {
                foundMarks++
            }
            x += TIMING_MARK_SPACING
        }
        
        // Check bottom edge timing marks
        x = 60.0
        while (x < 535) {
            expectedMarks++
            if (checkTimingMark(binary, warpedMat, x, OUTPUT_HEIGHT - TIMING_MARK_EDGE_OFFSET)) {
                foundMarks++
            }
            x += TIMING_MARK_SPACING
        }
        
        // Check left edge timing marks
        var y = 60.0
        while (y < 780) {
            expectedMarks++
            if (checkTimingMark(binary, warpedMat, TIMING_MARK_EDGE_OFFSET, y)) {
                foundMarks++
            }
            y += TIMING_MARK_SPACING
        }
        
        // Check right edge timing marks
        y = 60.0
        while (y < 780) {
            expectedMarks++
            if (checkTimingMark(binary, warpedMat, OUTPUT_WIDTH - TIMING_MARK_EDGE_OFFSET, y)) {
                foundMarks++
            }
            y += TIMING_MARK_SPACING
        }
        
        binary.release()
        
        debugInfo["timingMarksFound"] = foundMarks
        debugInfo["timingMarksExpected"] = expectedMarks
        
        return if (expectedMarks > 0) foundMarks.toDouble() / expectedMarks else 0.0
    }
    
    /**
     * Check if a timing mark exists at the given position
     */
    private fun checkTimingMark(binary: Mat, gray: Mat, x: Double, y: Double): Boolean {
        val radius = (TIMING_MARK_SIZE / 2 + 3).toInt()
        val cx = x.toInt().coerceIn(radius, binary.cols() - radius - 1)
        val cy = y.toInt().coerceIn(radius, binary.rows() - radius - 1)
        
        val roi = Mat(binary, Rect(cx - radius, cy - radius, radius * 2, radius * 2))
        val whitePixels = Core.countNonZero(roi)
        val totalPixels = roi.rows() * roi.cols()
        roi.release()
        val binaryFill = whitePixels.toDouble() / totalPixels

        val grayRoi = Mat(gray, Rect(cx - radius, cy - radius, radius * 2, radius * 2))
        val mean = Core.mean(grayRoi).`val`[0]
        grayRoi.release()
        val intensityFill = 1.0 - (mean / 255.0)

        // Accept either binary ink density or dark gray intensity (soft / blurry marks).
        return binaryFill > 0.10 || intensityFill > 0.42
    }
    
    /**
     * Detect and decode QR code from the header area
     */
    /**
     * Decode the sheet QR straight from the full-resolution capture.
     *
     * The graded warp is only [OUTPUT_WIDTH]x[OUTPUT_HEIGHT], so the printed QR
     * lands on ~80px there — under 2 pixels per module. Here we reuse the corner
     * homography but map ONLY the QR box to a magnified output, so the crop is
     * sampled from original camera pixels instead of an already-shrunken image.
     */
    private fun decodeQrFromSourceFrame(
        srcGray: Mat,
        corners: DetectedCorners,
        debugInfo: MutableMap<String, Any>,
    ): String? {
        val markerCenterOffset = CORNER_OFFSET + (CORNER_MARKER_SIZE / 2.0)
        val boxWidth = QR_BOX_RIGHT - QR_BOX_LEFT
        val boxHeight = QR_BOX_BOTTOM - QR_BOX_TOP

        for (scale in QR_SOURCE_CROP_SCALES) {
            val outWidth = (boxWidth * scale).toInt()
            val outHeight = (boxHeight * scale).toInt()
            if (outWidth < 80 || outHeight < 80 || outWidth > 1800 || outHeight > 1800) {
                continue
            }

            var srcPoints: MatOfPoint2f? = null
            var dstPoints: MatOfPoint2f? = null
            var transform: Mat? = null
            val cropped = Mat()
            try {
                srcPoints = MatOfPoint2f(
                    corners.topLeft,
                    corners.topRight,
                    corners.bottomRight,
                    corners.bottomLeft,
                )
                // Page point -> magnified QR-box pixel.
                fun dst(x: Double, y: Double) = Point(
                    x * scale - QR_BOX_LEFT * scale,
                    y * scale - QR_BOX_TOP * scale,
                )
                dstPoints = MatOfPoint2f(
                    dst(markerCenterOffset, markerCenterOffset),
                    dst(OUTPUT_WIDTH - markerCenterOffset, markerCenterOffset),
                    dst(OUTPUT_WIDTH - markerCenterOffset, OUTPUT_HEIGHT - markerCenterOffset),
                    dst(markerCenterOffset, OUTPUT_HEIGHT - markerCenterOffset),
                )

                transform = Imgproc.getPerspectiveTransform(srcPoints, dstPoints)
                Imgproc.warpPerspective(
                    srcGray,
                    cropped,
                    transform,
                    Size(outWidth.toDouble(), outHeight.toDouble()),
                    Imgproc.INTER_CUBIC,
                )

                val decoded = decodeQrFromGrayMat(
                    cropped,
                    debugInfo,
                    "src${scale.toInt()}x",
                    upscaleVariants = false,
                )
                if (!decoded.isNullOrEmpty()) {
                    debugInfo["qrDecodePath"] = "sourceCrop${scale.toInt()}x"
                    return decoded
                }
            } catch (e: Exception) {
                Log.w(TAG, "Source-resolution QR crop failed: ${e.message}")
            } finally {
                cropped.release()
                transform?.release()
                srcPoints?.release()
                dstPoints?.release()
            }
        }

        // Last resort at source scale: let ML Kit hunt the whole frame.
        return decodeQrWithMlKit(srcGray)?.also {
            debugInfo["qrDecodePath"] = "sourceFullFrame"
            debugInfo["qrEngine"] = "mlkit"
        }
    }

    private fun detectQRCode(warpedMat: Mat, debugInfo: MutableMap<String, Any>): String? {
        try {
            // Top-right header where the printed QR lives (≈80pt on 595-wide page).
            val regions = listOf(
                Rect(
                    (OUTPUT_WIDTH * 0.62).toInt(),
                    max(0, MARGIN_TOP.toInt() - 4),
                    (OUTPUT_WIDTH * 0.36).toInt(),
                    130,
                ),
                Rect(
                    (OUTPUT_WIDTH * 0.55).toInt(),
                    0,
                    (OUTPUT_WIDTH * 0.45).toInt(),
                    160,
                ),
            )

            for ((index, qrRegion) in regions.withIndex()) {
                val safeRegion = Rect(
                    qrRegion.x.coerceIn(0, warpedMat.cols() - 1),
                    qrRegion.y.coerceIn(0, warpedMat.rows() - 1),
                    qrRegion.width.coerceAtMost(warpedMat.cols() - qrRegion.x),
                    qrRegion.height.coerceAtMost(warpedMat.rows() - qrRegion.y),
                )
                if (safeRegion.width < 40 || safeRegion.height < 40) continue

                val qrRoi = Mat(warpedMat, safeRegion)
                val decoded = decodeQrFromGrayMat(qrRoi, debugInfo, "roi$index")
                qrRoi.release()
                if (!decoded.isNullOrEmpty()) {
                    Log.d(TAG, "QR Code detected via roi$index")
                    debugInfo["qrDecodePath"] = "roi$index"
                    return decoded
                }
            }

            val fullDecoded = decodeQrFromGrayMat(warpedMat, debugInfo, "full")
            if (!fullDecoded.isNullOrEmpty()) {
                Log.d(TAG, "QR Code detected (full scan)")
                debugInfo["qrDecodePath"] = "full"
                return fullDecoded
            }
        } catch (e: Exception) {
            Log.w(TAG, "QR detection error: ${e.message}")
            debugInfo["qrError"] = e.message ?: "Unknown"
        }

        return null
    }

    /**
     * Try ML Kit first (best on phone photos), then OpenCV with upscaled / CLAHE variants.
     */
    private fun decodeQrFromGrayMat(
        gray: Mat,
        debugInfo: MutableMap<String, Any>,
        tag: String,
        upscaleVariants: Boolean = true,
    ): String? {
        val mlKit = decodeQrWithMlKit(gray)
        if (!mlKit.isNullOrEmpty()) {
            debugInfo["qrEngine"] = "mlkit"
            debugInfo["qrEngineTag"] = tag
            return mlKit
        }

        val variants = buildList {
            add(gray)
            // Otsu binarization — printed QR is pure black/white, this removes
            // paper shading that trips both decoders.
            val binary = Mat()
            Imgproc.threshold(gray, binary, 0.0, 255.0, Imgproc.THRESH_BINARY + Imgproc.THRESH_OTSU)
            add(binary)
            if (upscaleVariants) {
                val up2 = Mat()
                Imgproc.resize(gray, up2, Size(), 2.0, 2.0, Imgproc.INTER_CUBIC)
                add(up2)
                val up3 = Mat()
                Imgproc.resize(gray, up3, Size(), 3.0, 3.0, Imgproc.INTER_CUBIC)
                add(up3)
            }
        }

        try {
            for ((i, variant) in variants.withIndex()) {
                if (i > 0) {
                    val mlVariant = decodeQrWithMlKit(variant)
                    if (!mlVariant.isNullOrEmpty()) {
                        debugInfo["qrEngine"] = "mlkit"
                        debugInfo["qrEngineTag"] = "$tag-v$i"
                        return mlVariant
                    }
                }
                val decoded = qrDetector.detectAndDecode(variant)
                if (decoded.isNotEmpty()) {
                    debugInfo["qrEngine"] = "opencv"
                    debugInfo["qrEngineTag"] = "$tag-v$i"
                    return decoded
                }
            }
        } finally {
            // Release clones only (index 0 is the caller's mat)
            for (i in 1 until variants.size) {
                variants[i].release()
            }
        }
        return null
    }

    private fun decodeQrWithMlKit(gray: Mat): String? {
        var bitmap: Bitmap? = null
        return try {
            bitmap = Bitmap.createBitmap(gray.cols(), gray.rows(), Bitmap.Config.ARGB_8888)
            Utils.matToBitmap(gray, bitmap)
            val image = InputImage.fromBitmap(bitmap, 0)
            val options = BarcodeScannerOptions.Builder()
                .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                .build()
            val scanner = BarcodeScanning.getClient(options)
            val barcodes = Tasks.await(scanner.process(image), 2500, TimeUnit.MILLISECONDS)
            scanner.close()
            barcodes.firstOrNull { !it.rawValue.isNullOrBlank() }?.rawValue
        } catch (e: Exception) {
            Log.d(TAG, "ML Kit QR decode skipped: ${e.message}")
            null
        } finally {
            bitmap?.recycle()
        }
    }
    
    /**
     * Parse layout metadata from QR payload v2
     * Returns null if QR data is v1 (no layout) or parsing fails
     */
    private fun parseSessionLayout(raw: Map<*, *>?): QrLayoutMetadata? {
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
        val columnWidth = readDouble("colWidth")
        val bubbleSpacingX = readDouble("bubbleSpacingX")

        if (templateId.isEmpty() || columns <= 0 || rows <= 0 || rowHeight <= 0.0) {
            return null
        }

        return QrLayoutMetadata(
            templateId = templateId,
            columns = columns,
            rows = rows,
            gridTop = readDouble("gridTop").takeIf { it > 0.0 } ?: ANSWER_GRID_TOP,
            gridBottom = readDouble("gridBottom").takeIf { it > 0.0 } ?: ANSWER_GRID_BOTTOM,
            rowHeight = rowHeight,
            columnWidth = columnWidth.takeIf { it > 0.0 } ?: (ANSWER_GRID_WIDTH / columns),
            bubbleSpacingX = bubbleSpacingX.takeIf { it > 0.0 } ?: 17.0,
        )
    }

    /**
     * Classify QR content as COC / foreign / none.
     * Returns: "coc" | "coc_legacy" | "foreign" | "none" | "unknown"
     */
    private fun classifyQrIdentity(
        qrData: String?,
        debugInfo: MutableMap<String, Any>,
    ): String {
        if (qrData.isNullOrBlank()) {
            return "none"
        }
        val trimmed = qrData.trim()
        if (!trimmed.startsWith("{")) {
            debugInfo["sheetQrKind"] = "non_json"
            return "foreign"
        }
        return try {
            val json = JSONObject(trimmed)
            val appCompact = json.optString("a", "").trim()
            val appVerbose = json.optString("app", "").trim()
            val app = appCompact.ifEmpty { appVerbose }
            when {
                app.equals("coc-omr", ignoreCase = true) -> "coc"
                app.isNotEmpty() -> {
                    debugInfo["sheetQrForeignApp"] = app
                    "foreign"
                }
                (json.has("id") || json.has("sheetId")) &&
                    (json.has("sn") || json.has("subjectName")) &&
                    (json.has("q") || json.has("questions")) -> "coc_legacy"
                (json.has("l") || json.has("layout")) && json.optInt("v", 0) >= 2 -> "coc_legacy"
                else -> {
                    debugInfo["sheetQrKind"] = "json_unknown"
                    "foreign"
                }
            }
        } catch (_: Exception) {
            debugInfo["sheetQrKind"] = "json_parse_error"
            "unknown"
        }
    }

    /**
     * Parse layout metadata from QR payload v2
     * Returns null if QR data is v1 (no layout) or parsing fails
     */
    private fun parseQrLayout(qrData: String?): QrLayoutMetadata? {
        if (qrData.isNullOrEmpty()) return null
        
        try {
            val json = JSONObject(qrData)
            val version = json.optInt("v", 1)
            
            // v1 payloads don't have layout metadata
            if (version < 2) {
                Log.d(TAG, "QR payload is v1 - no layout metadata, using calculated positions")
                return null
            }
            
            val layoutJson = json.optJSONObject("l")
                ?: json.optJSONObject("layout")
                ?: return null
            
            fun lStr(compact: String, verbose: String, def: String = "") =
                layoutJson.optString(compact, layoutJson.optString(verbose, def))
            fun lInt(compact: String, verbose: String, def: Int = 0) =
                if (layoutJson.has(compact)) layoutJson.optInt(compact, def)
                else layoutJson.optInt(verbose, def)
            fun lDbl(compact: String, verbose: String, def: Double = 0.0) =
                if (layoutJson.has(compact)) layoutJson.optDouble(compact, def)
                else layoutJson.optDouble(verbose, def)

            return QrLayoutMetadata(
                templateId = lStr("t", "template"),
                columns = lInt("c", "cols"),
                rows = lInt("r", "rows"),
                gridTop = lDbl("gt", "gridTop", ANSWER_GRID_TOP),
                gridBottom = lDbl("gb", "gridBottom", ANSWER_GRID_BOTTOM),
                rowHeight = lDbl("rh", "rowHeight"),
                columnWidth = lDbl("cw", "colWidth"),
                bubbleSpacingX = lDbl("bx", "bubbleSpacingX")
            ).also {
                Log.d(TAG, "Parsed QR layout v2: template=${it.templateId}, cols=${it.columns}, rows=${it.rows}, rowHeight=${it.rowHeight}")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse QR layout: ${e.message}")
            return null
        }
    }
    
    /**
     * Calculate fallback layout for v1 QR payloads (backward compatibility)
     */
    private fun calculateFallbackLayout(totalQuestions: Int): QrLayoutMetadata {
        val (columns, rows, bubbleSpacingX) = when {
            totalQuestions <= 30 -> Triple(3, 10, 26.0)
            totalQuestions <= 40 -> Triple(4, 10, 22.0)
            totalQuestions <= 50 -> Triple(5, 10, 17.0)
            totalQuestions <= 60 -> Triple(5, 12, 17.0)
            totalQuestions <= 70 -> Triple(5, 14, 17.0)
            totalQuestions <= 80 -> Triple(5, 16, 17.0)
            totalQuestions <= 90 -> Triple(5, 18, 17.0)
            else -> Triple(5, 20, 17.0)
        }
        val gridHeight = ANSWER_GRID_BOTTOM - ANSWER_GRID_TOP
        val gridWidth = ANSWER_GRID_RIGHT - ANSWER_GRID_LEFT
        
        return QrLayoutMetadata(
            templateId = "LEGACY",
            columns = columns,
            rows = rows,
            gridTop = ANSWER_GRID_TOP,
            gridBottom = ANSWER_GRID_BOTTOM,
            rowHeight = gridHeight / rows,
            columnWidth = gridWidth / columns,
            bubbleSpacingX = bubbleSpacingX
        )
    }
    
    /**
     * Validate row marks on the left edge to confirm template alignment
     * Returns a score from 0.0 (no marks detected) to 1.0 (all marks detected)
     */
    private fun validateRowMarks(
        warpedMat: Mat, 
        layout: QrLayoutMetadata, 
        debugInfo: MutableMap<String, Any>
    ): Double {
        try {
            var detectedMarks = 0
            val expectedMarks = layout.rows
            
            for (rowIndex in 0 until layout.rows) {
                // Calculate expected Y position for this row mark
                val rowCenterY = layout.gridTop + (rowIndex * layout.rowHeight) + (layout.rowHeight / 2)
                
                // Sample the row mark position (small square on left edge)
                val markX = ROW_MARK_X
                val markY = rowCenterY
                
                // Sample a small region around the expected mark position
                val sampleSize = (ROW_MARK_SIZE * 2).toInt()
                val x = (markX - sampleSize / 2).toInt().coerceIn(0, warpedMat.cols() - sampleSize)
                val y = (markY - sampleSize / 2).toInt().coerceIn(0, warpedMat.rows() - sampleSize)
                
                if (x >= 0 && y >= 0 && x + sampleSize < warpedMat.cols() && y + sampleSize < warpedMat.rows()) {
                    val roi = Mat(warpedMat, Rect(x, y, sampleSize, sampleSize))
                    val meanIntensity = Core.mean(roi).`val`[0]
                    roi.release()
                    
                    // Dark mark = low intensity (< 100)
                    if (meanIntensity < 100) {
                        detectedMarks++
                    }
                }
            }
            
            val score = detectedMarks.toDouble() / expectedMarks
            debugInfo["rowMarksDetected"] = detectedMarks
            debugInfo["rowMarksExpected"] = expectedMarks
            Log.d(TAG, "Row mark validation: $detectedMarks/$expectedMarks detected (score=$score)")
            
            return score
        } catch (e: Exception) {
            Log.w(TAG, "Row mark validation error: ${e.message}")
            return 0.5  // Uncertain - don't fail
        }
    }
    
    /**
     * Calibrate fill threshold using the calibration marks in the footer
     * Uses fixed positions from OmrPageConstants
     */
    private fun calibrateFillThreshold(warpedMat: Mat, debugInfo: MutableMap<String, Any>): GridCalibration {
        try {
            // Use fixed calibration mark positions from OmrPageConstants
            val filledFill = sampleBubbleFill(
                warpedMat,
                CALIBRATION_FILLED_X,
                CALIBRATION_Y,
                CALIBRATION_BUBBLE_SIZE,
            )
            val emptyFill = sampleBubbleFill(
                warpedMat,
                CALIBRATION_EMPTY_X,
                CALIBRATION_Y,
                CALIBRATION_BUBBLE_SIZE,
            )
            
            debugInfo["calibrationFilledSample"] = filledFill
            debugInfo["calibrationEmptySample"] = emptyFill
            debugInfo["calibrationFilledX"] = CALIBRATION_FILLED_X
            debugInfo["calibrationEmptyX"] = CALIBRATION_EMPTY_X
            debugInfo["calibrationY"] = CALIBRATION_Y
            
            // If we got good samples, calculate threshold.
            // Midpoint between solid black and empty paper sits too high for light pencil;
            // place the cut ~40% up from empty and clamp to a pencil-safe band.
            if (filledFill > emptyFill + 0.10) {
                val gap = filledFill - emptyFill
                val threshold = (emptyFill + gap * 0.40).coerceIn(0.28, 0.42)
                Log.d(TAG, "Calibration successful: filled=$filledFill, empty=$emptyFill, threshold=$threshold")
                return GridCalibration(
                    fillThreshold = threshold,
                    emptyAverage = emptyFill,
                    filledAverage = filledFill,
                    isCalibrated = true
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "Calibration error: ${e.message}")
        }
        
        return GridCalibration(
            fillThreshold = DEFAULT_FILL_THRESHOLD,
            emptyAverage = 0.0,
            filledAverage = 0.0,
            isCalibrated = false
        )
    }
    
    /**
     * Sample the fill percentage of a bubble at a given position
     */
    private fun sampleBubbleFill(
        grayMat: Mat,
        centerX: Double,
        centerY: Double,
        diameter: Double = BUBBLE_DIAMETER,
    ): Double {
        val radius = (diameter / 2 + 2).toInt()
        val x = (centerX - radius).toInt().coerceIn(0, grayMat.cols() - radius * 2)
        val y = (centerY - radius).toInt().coerceIn(0, grayMat.rows() - radius * 2)
        
        val roi = Mat(grayMat, Rect(x, y, radius * 2, radius * 2))
        val mean = Core.mean(roi).`val`[0]
        roi.release()
        
        // Convert to fill percentage (lower intensity = more filled)
        return 1.0 - (mean / 255.0)
    }
    
    /**
     * Detect OMR ID with validation
     */
    private fun detectOmrIdWithValidation(thresholdMat: Mat, grayMat: Mat, fillThreshold: Double,
                                           debugInfo: MutableMap<String, Any>): OmrIdReadResult? {
        // Use fixed OMR ID positions from OmrPageConstants
        debugInfo["omrIdFirstColumnX"] = OMR_ID_FIRST_COLUMN_X
        debugInfo["omrIdFirstRowY"] = OMR_ID_FIRST_ROW_Y
        debugInfo["omrIdColumnSpacing"] = OMR_ID_COLUMN_SPACING
        debugInfo["omrIdRowSpacing"] = OMR_ID_ROW_SPACING
        
        // Pencil fills often land below the solid-black calibration ceiling (0.42).
        // Use a slightly lower cut for OMR ID only — answer bubbles keep fillThreshold.
        val minSeparation = 0.10
        val nearZeroLevel = fillThreshold * 0.5
        val omrIdCut = maxOf(nearZeroLevel, fillThreshold - 0.10)
        debugInfo["omrIdFillCut"] = omrIdCut
        
        val bestDigits = IntArray(OMR_ID_COLUMNS) { -1 }
        val confidences = DoubleArray(OMR_ID_COLUMNS) { 0.0 }
        val columnStatuses = arrayOfNulls<String>(OMR_ID_COLUMNS)  // "ok" | "ambiguous" | "nearZero"
        var nearZeroCount = 0
        var ambiguousCount = 0
        
        for (col in 0 until OMR_ID_COLUMNS) {
            // Fixed column positions from OmrPageConstants
            val columnX = OMR_ID_FIRST_COLUMN_X + col * OMR_ID_COLUMN_SPACING
            var bestDigit = -1
            var bestFill = 0.0
            var secondBestFill = 0.0
            
            // Scan all 10 digit positions
            for (digit in 0 until OMR_ID_ROWS) {
                // Fixed row positions from OmrPageConstants
                val bubbleY = OMR_ID_FIRST_ROW_Y + digit * OMR_ID_ROW_SPACING
                // OMR ID rows are only ~12pt apart — use tiny refine (±1) so we do not
                // pull fill from the neighboring digit bubble.
                val result = analyzeBubbleWithRefine(
                    thresholdMat, grayMat, columnX, bubbleY, fillThreshold,
                    refineRadius = 1,
                )
                
                if (result.fillPercentage > bestFill) {
                    secondBestFill = bestFill
                    bestFill = result.fillPercentage
                    bestDigit = digit
                } else if (result.fillPercentage > secondBestFill) {
                    secondBestFill = result.fillPercentage
                }
            }
            
            val separation = bestFill - secondBestFill
            bestDigits[col] = bestDigit
            confidences[col] = minOf(separation / 0.2, 1.0)  // Good if >0.2 separation
            
            val status = when {
                bestFill < nearZeroLevel -> { nearZeroCount++; "nearZero" }
                bestDigit >= 0 && bestFill > omrIdCut &&
                    separation >= minSeparation -> "ok"
                else -> { ambiguousCount++; "ambiguous" }
            }
            columnStatuses[col] = status
            
            debugInfo["omrIdColumn${col}"] = mapOf(
                "bestDigit" to bestDigit,
                "bestFill" to bestFill,
                "secondFill" to secondBestFill,
                "status" to status
            )
        }
        
        debugInfo["omrIdColumnStatuses"] = columnStatuses.map { it ?: "unknown" }
        debugInfo["omrIdNearZeroColumns"] = nearZeroCount
        debugInfo["omrIdAmbiguousColumns"] = ambiguousCount
        debugInfo["omrIdDigitConfidences"] = confidences.toList()
        
        // Distinct case: nothing filled in any column -> "ID not filled in".
        if (nearZeroCount == OMR_ID_COLUMNS) {
            debugInfo["omrIdNotFilled"] = true
            return null
        }
        
        val problemColumns = nearZeroCount + ambiguousCount
        
        // All four columns clean -> full-confidence read.
        if (problemColumns == 0) {
            val id = bestDigits.joinToString("") { it.toString() }.padStart(4, '0')
            return OmrIdReadResult(id, confidences.average(), needsReview = false, ambiguousColumn = -1)
        }
        
        // Exactly one problem column (ambiguous or blank) and the other three clean:
        // return a best-guess ID flagged for manual review instead of failing.
        if (problemColumns == 1) {
            val problemCol = (0 until OMR_ID_COLUMNS).first { columnStatuses[it] != "ok" }
            // Keep a numeric best guess so roster lookup can still match the student;
            // the review flag tells the teacher which digit to verify.
            val id = bestDigits
                .joinToString("") { if (it >= 0) it.toString() else "0" }
                .padStart(4, '0')
            debugInfo["omrIdNeedsReview"] = true
            debugInfo["omrIdAmbiguousColumn"] = problemCol
            return OmrIdReadResult(
                id,
                confidences.average() * 0.6,
                needsReview = true,
                ambiguousColumn = problemCol
            )
        }
        
        // Two or more unreadable columns -> genuinely unreadable.
        debugInfo["omrIdUnreadable"] = true
        return null
    }
    
    /**
     * Detect answers with cross-validation
     */
    private fun detectAnswersWithValidation(thresholdMat: Mat, grayMat: Mat, totalQuestions: Int,
                                             fillThreshold: Double, debugInfo: MutableMap<String, Any>): Pair<Map<Int, String>, Double> {
        // Legacy answer-section fallback now uses the same fixed shared bounds.
        val answerSectionTop = ANSWER_GRID_TOP
        val answerSectionBottom = ANSWER_GRID_BOTTOM
        val answerSectionLeft = ANSWER_GRID_LEFT
        val answerSectionRight = ANSWER_GRID_RIGHT
        
        val answerSectionHeight = answerSectionBottom - answerSectionTop
        val answerSectionWidth = answerSectionRight - answerSectionLeft
        
        val legacyLayout = calculateFallbackLayout(totalQuestions)
        val columnCount = legacyLayout.columns
        val questionsPerColumn = legacyLayout.rows
        
        val columnWidth = answerSectionWidth / columnCount
        val rowHeight = answerSectionHeight / questionsPerColumn
        
        val answers = mutableMapOf<Int, String>()
        val confidences = mutableListOf<Double>()
        val options = listOf("A", "B", "C", "D", "E")
        val ambiguousQuestions = mutableListOf<Int>()
        
        var multipleSelections = 0
        var noSelections = 0
        
        for (questionNum in 1..totalQuestions) {
            val col = (questionNum - 1) / questionsPerColumn
            val row = (questionNum - 1) % questionsPerColumn
            
            if (col >= columnCount) break
            
            val columnLeft = answerSectionLeft + col * columnWidth
            val rowCenterY = answerSectionTop + (row + 0.5) * rowHeight
            
            // Bubble positions centered the same way as the shared layout.
            val bubbleSpacing = legacyLayout.bubbleSpacingX
            val bubbleAreaWidth = bubbleSpacing * (ANSWER_OPTIONS - 1)
            val usableWidth = columnWidth - (ANSWER_COLUMN_INSET * 2)
            val rowContentWidth = QUESTION_NUMBER_WIDTH +
                    ANSWER_NUMBER_BUBBLE_GAP +
                    bubbleAreaWidth
            val rowContentLeft = columnLeft +
                    ANSWER_COLUMN_INSET +
                    ((usableWidth - rowContentWidth) / 2)
            val bubbleAreaLeft = rowContentLeft +
                    QUESTION_NUMBER_WIDTH +
                    ANSWER_NUMBER_BUBBLE_GAP
            
            var bestOption = ""
            var bestFill = 0.0
            var secondBestFill = 0.0
            val optionFills = mutableListOf<Double>()
            
            for ((optIdx, option) in options.withIndex()) {
                val bubbleX = bubbleAreaLeft + (optIdx * bubbleSpacing)
                val result = analyzeBubblePrecise(thresholdMat, grayMat, bubbleX, rowCenterY, fillThreshold)
                optionFills.add(result.fillPercentage)
                
                if (result.fillPercentage > bestFill) {
                    secondBestFill = bestFill
                    bestFill = result.fillPercentage
                    bestOption = option
                } else if (result.fillPercentage > secondBestFill) {
                    secondBestFill = result.fillPercentage
                }
            }
            
            // Check for multiple selections
            val filledCount = optionFills.count { it > fillThreshold }
            if (filledCount > 1) {
                multipleSelections++
                ambiguousQuestions.add(questionNum)
                continue
            }
            if (filledCount == 0) {
                noSelections++
            }
            
            if (bestOption.isNotEmpty() && bestFill > fillThreshold) {
                val separation = bestFill - secondBestFill
                val confidence = minOf(separation / 0.15, 1.0)
                
                answers[questionNum] = bestOption
                confidences.add(confidence)
            }
        }
        
        debugInfo["multipleSelections"] = multipleSelections
        debugInfo["noSelections"] = noSelections
        debugInfo["ambiguousQuestions"] = ambiguousQuestions.toList()
        
        val avgConfidence = if (confidences.isNotEmpty()) confidences.average() else 0.0
        return Pair(answers, avgConfidence)
    }
    
    /**
     * NEW: Detect answers using layout metadata from QR (v2) or fallback layout
     * This uses fixed positions from the template specs instead of calculating them dynamically
     */
    private fun detectAnswersWithLayout(
        thresholdMat: Mat, 
        grayMat: Mat, 
        totalQuestions: Int,
        layout: QrLayoutMetadata,
        fillThreshold: Double, 
        debugInfo: MutableMap<String, Any>
    ): Pair<Map<Int, String>, Double> {
        
        val answers = mutableMapOf<Int, String>()
        val confidences = mutableListOf<Double>()
        val options = listOf("A", "B", "C", "D", "E")
        val ambiguousQuestions = mutableListOf<Int>()
        
        var multipleSelections = 0
        var noSelections = 0
        var bestFillSum = 0.0
        var maxOptionFill = 0.0
        
        // Use fixed positions from layout metadata.
        // gridTop is the actual first-row grid origin on the printed sheet.
        val contentTop = layout.gridTop
        val rowHeight = layout.rowHeight
        val columnWidth = layout.columnWidth
        val bubbleSpacingX = layout.bubbleSpacingX
        val columns = layout.columns
        val rows = layout.rows
        
        Log.d(TAG, "Detecting answers with layout: contentTop=$contentTop, rowHeight=$rowHeight, " +
                "colWidth=$columnWidth, bubbleSpacing=$bubbleSpacingX, cols=$columns, rows=$rows")
        
        for (questionNum in 1..totalQuestions) {
            // Calculate position using template's fixed layout
            val col = (questionNum - 1) / rows
            val row = (questionNum - 1) % rows
            
            if (col >= columns) break
            
            // Fixed column center X (using template's column width)
            val columnCenterX = ANSWER_GRID_LEFT + (col * columnWidth) + (columnWidth / 2)
            
            // Fixed row center Y using the shared template grid origin.
            val rowCenterY = contentTop + (row * rowHeight) + (rowHeight / 2)
            
            // Bubble positions using fixed spacing from template
            val bubbleAreaWidth = bubbleSpacingX * (ANSWER_OPTIONS - 1)
            val usableWidth = columnWidth - (ANSWER_COLUMN_INSET * 2)
            val rowContentWidth = QUESTION_NUMBER_WIDTH +
                    ANSWER_NUMBER_BUBBLE_GAP +
                    bubbleAreaWidth
            val rowContentLeft = (ANSWER_GRID_LEFT + (col * columnWidth)) +
                    ANSWER_COLUMN_INSET +
                    ((usableWidth - rowContentWidth) / 2)
            val bubbleAreaLeft = rowContentLeft +
                    QUESTION_NUMBER_WIDTH +
                    ANSWER_NUMBER_BUBBLE_GAP
            
            var bestOption = ""
            var bestFill = 0.0
            var secondBestFill = 0.0
            val optionFills = mutableListOf<Double>()
            
            for ((optIdx, option) in options.withIndex()) {
                val bubbleX = bubbleAreaLeft + (optIdx * bubbleSpacingX)
                val result = analyzeBubbleWithRefine(thresholdMat, grayMat, bubbleX, rowCenterY, fillThreshold)
                optionFills.add(result.fillPercentage)
                if (result.fillPercentage > maxOptionFill) {
                    maxOptionFill = result.fillPercentage
                }
                
                if (result.fillPercentage > bestFill) {
                    secondBestFill = bestFill
                    bestFill = result.fillPercentage
                    bestOption = option
                } else if (result.fillPercentage > secondBestFill) {
                    secondBestFill = result.fillPercentage
                }
            }
            bestFillSum += bestFill
            
            // Check for multiple selections
            val filledCount = optionFills.count { it > fillThreshold }
            if (filledCount > 1) {
                multipleSelections++
                ambiguousQuestions.add(questionNum)
                continue
            }
            if (filledCount == 0) {
                noSelections++
            }
            
            if (bestOption.isNotEmpty() && bestFill > fillThreshold) {
                val separation = bestFill - secondBestFill
                val confidence = minOf(separation / 0.15, 1.0)
                
                answers[questionNum] = bestOption
                confidences.add(confidence)
            }
        }
        
        debugInfo["multipleSelectionsLayout"] = multipleSelections
        debugInfo["noSelectionsLayout"] = noSelections
        debugInfo["ambiguousQuestions"] = ambiguousQuestions.toList()
        debugInfo["meanBestOptionFill"] = if (totalQuestions > 0) bestFillSum / totalQuestions else 0.0
        debugInfo["maxOptionFill"] = maxOptionFill
        
        val avgConfidence = if (confidences.isNotEmpty()) confidences.average() else 0.0
        return Pair(answers, avgConfidence)
    }
    
    /**
     * Bubble sample with a capped dark-centroid refine.
     *
     * Max-fill search across ±N px is unsafe: answer options are ~17pt apart and OMR ID
     * digits ~12pt, so maximizing fill slides empty ROIs into neighboring ink and invents
     * marks. Instead, pull the sample center toward the dark mass only when enough dark
     * pixels exist inside the search window (true filled bubble), otherwise stay put.
     */
    private fun analyzeBubbleWithRefine(
        thresholdMat: Mat,
        grayMat: Mat,
        centerX: Double,
        centerY: Double,
        fillThreshold: Double,
        refineRadius: Int = BUBBLE_REFINE_RADIUS_PX,
    ): BubbleResult {
        val (rx, ry) = darkCentroidOffset(grayMat, centerX, centerY, refineRadius)
        return analyzeBubblePrecise(
            thresholdMat,
            grayMat,
            centerX + rx,
            centerY + ry,
            fillThreshold,
        )
    }

    /**
     * Returns (dx, dy) toward the intensity-weighted dark centroid, capped to [refineRadius].
     * Returns (0,0) when the window is not dark enough (empty / paper).
     */
    private fun darkCentroidOffset(
        grayMat: Mat,
        centerX: Double,
        centerY: Double,
        refineRadius: Int,
    ): Pair<Double, Double> {
        if (refineRadius <= 0) return 0.0 to 0.0
        val cx = centerX.toInt().coerceIn(refineRadius, grayMat.cols() - refineRadius - 1)
        val cy = centerY.toInt().coerceIn(refineRadius, grayMat.rows() - refineRadius - 1)

        var sumW = 0.0
        var sumX = 0.0
        var sumY = 0.0
        // Pixels darker than ~paper mid-gray contribute; white paper contributes ~0.
        for (dy in -refineRadius..refineRadius) {
            for (dx in -refineRadius..refineRadius) {
                val v = grayMat.get(cy + dy, cx + dx)[0]
                val w = (200.0 - v).coerceAtLeast(0.0)
                if (w <= 0.0) continue
                sumW += w
                sumX += dx * w
                sumY += dy * w
            }
        }

        // Empty bubbles / plain paper rarely accumulate enough dark weight.
        val minWeight = refineRadius * refineRadius * 12.0
        if (sumW < minWeight) return 0.0 to 0.0

        val dx = (sumX / sumW).coerceIn(-refineRadius.toDouble(), refineRadius.toDouble())
        val dy = (sumY / sumW).coerceIn(-refineRadius.toDouble(), refineRadius.toDouble())
        return dx to dy
    }

    private fun analyzeBubblePrecise(
        thresholdMat: Mat,
        grayMat: Mat,
        centerX: Double,
        centerY: Double,
        fillThreshold: Double = DEFAULT_FILL_THRESHOLD,
    ): BubbleResult {
        val radius = (BUBBLE_DIAMETER / 2 + 1).toInt()
        
        // Ensure within bounds
        val x = (centerX - radius).toInt().coerceIn(0, thresholdMat.cols() - radius * 2 - 1)
        val y = (centerY - radius).toInt().coerceIn(0, thresholdMat.rows() - radius * 2 - 1)
        val size = (radius * 2).coerceAtMost(minOf(thresholdMat.cols() - x, thresholdMat.rows() - y))
        
        if (size <= 4) {
            return BubbleResult(false, 0.0, 0.0, centerX, centerY)
        }
        
        // Method 1: Threshold-based fill
        val threshRoi = Mat(thresholdMat, Rect(x, y, size, size))
        val mask = Mat.zeros(size, size, CvType.CV_8UC1)
        // Keep mask inside the printed ring so border ink does not inflate empty bubbles.
        val maskRadius = maxOf(2, (size * 0.32).toInt())
        Imgproc.circle(mask, Point(size / 2.0, size / 2.0), maskRadius, Scalar(255.0), -1)
        
        val maskedRoi = Mat()
        Core.bitwise_and(threshRoi, mask, maskedRoi)
        val whitePixels = Core.countNonZero(maskedRoi)
        val totalPixels = Core.countNonZero(mask)
        
        val thresholdFill = if (totalPixels > 0) whitePixels.toDouble() / totalPixels else 0.0
        
        // Method 2: Intensity-based fill (from grayscale)
        val grayRoi = Mat(grayMat, Rect(x, y, size, size))
        val maskedGray = Mat()
        grayRoi.copyTo(maskedGray, mask)
        val meanIntensity = Core.mean(grayRoi, mask).`val`[0]
        val intensityFill = 1.0 - (meanIntensity / 255.0)
        
        // Combine both methods (average)
        // Heavier weight on grayscale intensity helps light pencil shading register.
        val combinedFill = (thresholdFill * 0.35) + (intensityFill * 0.65)
        
        // Calculate confidence based on consistency between methods
        val consistency = 1.0 - abs(thresholdFill - intensityFill)
        val confidence = when {
            combinedFill > 0.5 -> consistency * 0.95
            combinedFill > 0.35 -> consistency * 0.8
            combinedFill < 0.15 -> consistency * 0.95
            else -> consistency * 0.5
        }
        
        threshRoi.release()
        grayRoi.release()
        mask.release()
        maskedRoi.release()
        maskedGray.release()
        
        return BubbleResult(
            filled = combinedFill > fillThreshold,
            fillPercentage = combinedFill,
            confidence = confidence,
            centerX = centerX,
            centerY = centerY
        )
    }

    /**
     * Draw predicted bubble ROIs + chosen answers on the warped page for visual QA.
     * Stored as a compact JPEG base64 string in [debugInfo].
     */
    private fun attachDebugOverlay(
        warpedMat: Mat,
        layout: QrLayoutMetadata,
        answers: Map<Int, String>,
        fillThreshold: Double,
        debugInfo: MutableMap<String, Any>,
    ) {
        var color: Mat? = null
        try {
            color = Mat()
            Imgproc.cvtColor(warpedMat, color, Imgproc.COLOR_GRAY2BGR)
            val green = Scalar(40.0, 180.0, 40.0)
            val red = Scalar(40.0, 40.0, 220.0)
            val cyan = Scalar(220.0, 180.0, 40.0)
            val options = listOf("A", "B", "C", "D", "E")
            val maxQ = minOf(layout.columns * layout.rows, 100)

            for (questionNum in 1..maxQ) {
                val col = (questionNum - 1) / layout.rows
                val row = (questionNum - 1) % layout.rows
                if (col >= layout.columns) break
                val rowCenterY = layout.gridTop + (row * layout.rowHeight) + (layout.rowHeight / 2)
                val bubbleAreaWidth = layout.bubbleSpacingX * (ANSWER_OPTIONS - 1)
                val usableWidth = layout.columnWidth - (ANSWER_COLUMN_INSET * 2)
                val rowContentWidth = QUESTION_NUMBER_WIDTH + ANSWER_NUMBER_BUBBLE_GAP + bubbleAreaWidth
                val rowContentLeft = (ANSWER_GRID_LEFT + (col * layout.columnWidth)) +
                    ANSWER_COLUMN_INSET + ((usableWidth - rowContentWidth) / 2)
                val bubbleAreaLeft = rowContentLeft + QUESTION_NUMBER_WIDTH + ANSWER_NUMBER_BUBBLE_GAP
                val chosen = answers[questionNum]
                for ((optIdx, option) in options.withIndex()) {
                    val bubbleX = bubbleAreaLeft + (optIdx * layout.bubbleSpacingX)
                    val colorScalar = when {
                        chosen == option -> green
                        chosen != null -> cyan
                        else -> red
                    }
                    Imgproc.circle(
                        color,
                        Point(bubbleX, rowCenterY),
                        (BUBBLE_DIAMETER / 2).toInt(),
                        colorScalar,
                        1,
                    )
                }
            }

            // Timing mark expected sites (top edge sample)
            var x = 60.0
            while (x < 535) {
                Imgproc.circle(
                    color,
                    Point(x, TIMING_MARK_EDGE_OFFSET),
                    (TIMING_MARK_SIZE / 2).toInt(),
                    Scalar(255.0, 128.0, 0.0),
                    1,
                )
                x += TIMING_MARK_SPACING
            }

            // OMR ID digit ROIs — teachers need to see what was sampled when ID fails.
            val amber = Scalar(0.0, 165.0, 255.0)
            val grey = Scalar(140.0, 140.0, 140.0)
            for (col in 0 until OMR_ID_COLUMNS) {
                @Suppress("UNCHECKED_CAST")
                val colInfo = debugInfo["omrIdColumn$col"] as? Map<String, Any>
                val bestDigit = (colInfo?.get("bestDigit") as? Number)?.toInt() ?: -1
                val status = colInfo?.get("status")?.toString() ?: "unknown"
                val columnX = OMR_ID_FIRST_COLUMN_X + col * OMR_ID_COLUMN_SPACING
                for (digit in 0 until OMR_ID_ROWS) {
                    val bubbleY = OMR_ID_FIRST_ROW_Y + digit * OMR_ID_ROW_SPACING
                    val ring = when {
                        digit == bestDigit && status == "ok" -> green
                        digit == bestDigit && status == "ambiguous" -> amber
                        digit == bestDigit -> red
                        else -> grey
                    }
                    Imgproc.circle(
                        color,
                        Point(columnX, bubbleY),
                        4,
                        ring,
                        if (digit == bestDigit) 2 else 1,
                    )
                }
            }

            // Calibration reference bubbles
            Imgproc.circle(
                color,
                Point(CALIBRATION_FILLED_X, CALIBRATION_Y),
                (BUBBLE_DIAMETER / 2).toInt(),
                green,
                1,
            )
            Imgproc.circle(
                color,
                Point(CALIBRATION_EMPTY_X, CALIBRATION_Y),
                (BUBBLE_DIAMETER / 2).toInt(),
                cyan,
                1,
            )

            val jpeg = matToJpegBase64(color, quality = 45) ?: return
            debugInfo["debugOverlayJpegBase64"] = jpeg
            debugInfo["debugOverlayNote"] =
                "Green=chosen / ID ok, amber=ID uncertain, cyan=other options, " +
                    "red=blank answer or weak ID, grey=other ID digits, orange=timing"
            debugInfo["fillThresholdUsed"] = fillThreshold
        } catch (e: Exception) {
            Log.w(TAG, "Debug overlay failed: ${e.message}")
        } finally {
            color?.release()
        }
    }

    private fun matToJpegBase64(bgrMat: Mat, quality: Int): String? {
        val bitmap = Bitmap.createBitmap(bgrMat.cols(), bgrMat.rows(), Bitmap.Config.ARGB_8888)
        Utils.matToBitmap(bgrMat, bitmap)
        val stream = ByteArrayOutputStream()
        val ok = bitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream)
        bitmap.recycle()
        if (!ok) return null
        return Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
    }
    
    /**
     * Calculate overall confidence from all detection stages
     */
    private fun calculateOverallConfidence(
        timingMarkScore: Double,
        calibrationSuccess: Boolean,
        omrIdConfidence: Double,
        answersConfidence: Double,
        qrDetected: Boolean,
        debugInfo: MutableMap<String, Any>
    ): Double {
        var confidence = 1.0
        
        // Timing marks (alignment quality)
        confidence *= (0.7 + timingMarkScore * 0.3)
        
        // Calibration
        if (!calibrationSuccess) {
            confidence *= 0.9  // 10% penalty
        }
        
        // OMR ID confidence
        confidence *= (0.5 + omrIdConfidence * 0.5)
        
        // Answers confidence
        confidence *= (0.5 + answersConfidence * 0.5)
        
        // QR code detection is a bonus
        if (qrDetected) {
            confidence = minOf(confidence * 1.05, 1.0)
        }
        
        debugInfo["confidenceBreakdown"] = mapOf(
            "timingMarkFactor" to (0.7 + timingMarkScore * 0.3),
            "calibrationFactor" to if (calibrationSuccess) 1.0 else 0.9,
            "omrIdFactor" to (0.5 + omrIdConfidence * 0.5),
            "answersFactor" to (0.5 + answersConfidence * 0.5),
            "qrBonus" to if (qrDetected) 1.05 else 1.0
        )
        
        return confidence.coerceIn(0.0, 1.0)
    }
}

