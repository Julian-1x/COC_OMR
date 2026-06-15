package edu.coc.omr

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import org.opencv.android.Utils
import org.opencv.core.*
import org.opencv.imgproc.Imgproc
import org.opencv.objdetect.QRCodeDetector
import org.json.JSONObject
import org.json.JSONArray
import kotlin.math.*
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
class OmrProcessor {
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
        private const val DEFAULT_FILL_THRESHOLD = 0.40  // 40% fill = marked
        
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
        
        // Low-end device optimization constants
        private const val MAX_IMAGE_DIMENSION = 1600  // Max dimension before downscaling
        private const val LOW_MEMORY_THRESHOLD_MB = 150  // Consider device low-memory if < 150MB free
        private const val PROCESSING_TIMEOUT_MS = 15000L  // 15 second timeout
        private const val MAX_IMAGE_SIZE_BYTES = 20 * 1024 * 1024  // 20MB max input
        
        // Low-quality camera handling constants
        private const val MIN_BLUR_THRESHOLD = 100.0  // Laplacian variance threshold for blur detection
        private const val MIN_CONTRAST_RATIO = 1.5  // Minimum contrast ratio for reliable detection
        private const val NOISE_THRESHOLD = 15.0  // Max acceptable noise level
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
                put("debugInfo", JSONObject(debugInfo.mapValues { 
                    when (val v = it.value) {
                        is List<*> -> JSONArray(v)
                        else -> v
                    }
                }))
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
            
            // Widths and heights should be similar (within 20%)
            val widthRatio = minOf(width1, width2) / maxOf(width1, width2)
            val heightRatio = minOf(height1, height2) / maxOf(height1, height2)
            
            return widthRatio > 0.8 && heightRatio > 0.8
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
     * Determine processing quality based on available memory
     */
    private fun determineProcessingQuality(): ProcessingQuality {
        val runtime = Runtime.getRuntime()
        val freeMemoryMB = (runtime.freeMemory() / 1024 / 1024).toInt()
        val maxMemoryMB = (runtime.maxMemory() / 1024 / 1024).toInt()
        val availableRatio = freeMemoryMB.toFloat() / maxMemoryMB
        
        Log.d(TAG, "Memory: ${freeMemoryMB}MB free / ${maxMemoryMB}MB max (${(availableRatio * 100).toInt()}%)")
        
        return when {
            freeMemoryMB < 80 -> ProcessingQuality.FAST
            freeMemoryMB < LOW_MEMORY_THRESHOLD_MB -> ProcessingQuality.BALANCED
            else -> ProcessingQuality.HIGH
        }
    }
    
    /**
     * Check if we have enough memory to process
     */
    private fun checkMemoryAvailable(requiredMB: Int = 50): Boolean {
        val runtime = Runtime.getRuntime()
        val freeMemoryMB = runtime.freeMemory() / 1024 / 1024
        
        if (freeMemoryMB < requiredMB) {
            Log.w(TAG, "Low memory warning: ${freeMemoryMB}MB free, ${requiredMB}MB required")
            // Request garbage collection
            System.gc()
            return freeMemoryMB >= requiredMB / 2  // Still allow if at least half available
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
        val debugInfo = mutableMapOf<String, Any>()
        val startTime = System.currentTimeMillis()
        
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
        
        // Determine processing quality based on device capability
        val quality = determineProcessingQuality()
        debugInfo["processingQuality"] = quality.name
        Log.d(TAG, "Using processing quality: $quality")
        
        // Mats for cleanup (use nullable for safety)
        var originalMat: Mat? = null
        var grayMat: Mat? = null
        var warpedMat: Mat? = null
        var thresholdMat: Mat? = null
        var bitmap: Bitmap? = null
        
        try {
            // Step 1: Decode image with memory-efficient options
            val options = BitmapFactory.Options().apply {
                // For very large images, sample down during decode
                inJustDecodeBounds = true
            }
            BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size, options)
            
            val imageWidth = options.outWidth
            val imageHeight = options.outHeight
            
            // Calculate sample size for very large images (>4000px)
            var sampleSize = 1
            val maxDim = maxOf(imageWidth, imageHeight)
            if (maxDim > 4000) {
                sampleSize = 2
            } else if (maxDim > 6000) {
                sampleSize = 4
            }
            
            options.inJustDecodeBounds = false
            options.inSampleSize = sampleSize
            options.inPreferredConfig = Bitmap.Config.RGB_565  // Use less memory (2 bytes vs 4)
            
            bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size, options)
            if (bitmap == null) {
                return errorResult("Failed to decode image", debugInfo)
            }
            
            // Further downscale if still too large
            bitmap = downscaleIfNeeded(bitmap, MAX_IMAGE_DIMENSION)
            
            debugInfo["imageWidth"] = bitmap.width
            debugInfo["imageHeight"] = bitmap.height
            debugInfo["sampleSize"] = sampleSize
            Log.d(TAG, "Image decoded: ${bitmap.width}x${bitmap.height} (sampled: $sampleSize)")
            
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
            
            if (!imageQuality.isAcceptable) {
                // Try to enhance the image before giving up
                Log.w(TAG, "Image quality issues: ${imageQuality.issues}. Attempting enhancement...")
                enhanceImageForLowQualityCamera(grayMat, imageQuality)
                debugInfo["imageEnhanced"] = true
            }
            
            // Step 4: Detect corner markers using quality-appropriate method
            val corners = detectCornerMarkersAdaptive(grayMat, quality, debugInfo)
            if (corners == null || !corners.isValid()) {
                // Provide specific feedback based on quality issues
                val errorMsg = buildCornerDetectionErrorMessage(imageQuality)
                return errorResult(errorMsg, debugInfo)
            }
            
            debugInfo["cornersDetected"] = true
            debugInfo["cornerPositions"] = listOf(
                listOf(corners.topLeft.x, corners.topLeft.y),
                listOf(corners.topRight.x, corners.topRight.y),
                listOf(corners.bottomLeft.x, corners.bottomLeft.y),
                listOf(corners.bottomRight.x, corners.bottomRight.y)
            )
            Log.d(TAG, "Corners detected and validated")
            
            // Check timeout
            if (System.currentTimeMillis() - startTime > PROCESSING_TIMEOUT_MS * 2 / 3) {
                Log.w(TAG, "Corner detection took long - simplifying remaining steps")
            }
            
            // Step 5: Apply perspective transform
            warpedMat = applyPerspectiveTransform(grayMat, corners)
            debugInfo["warpedSize"] = "${warpedMat.cols()}x${warpedMat.rows()}"
            
            // Release grayscale since we have warped
            grayMat.release()
            grayMat = null
            
            // Step 6: Validate alignment using timing marks (skip in FAST mode)
            val timingMarkScore = if (quality == ProcessingQuality.FAST) {
                0.75  // Assume reasonable alignment in fast mode
            } else {
                validateTimingMarks(warpedMat, debugInfo)
            }
            debugInfo["timingMarkScore"] = timingMarkScore
            if (timingMarkScore < 0.5) {
                Log.w(TAG, "Low timing mark score: $timingMarkScore - alignment may be off")
            }
            
            // Step 7: Detect QR code (skip in FAST mode - it's slow)
            val qrData = if (quality == ProcessingQuality.FAST) {
                Log.d(TAG, "Skipping QR detection in FAST mode")
                null
            } else {
                detectQRCode(warpedMat, debugInfo)
            }
            debugInfo["qrDetected"] = qrData != null
            
            // Step 7.5: Parse layout from QR (v2) or calculate fallback (v1/no QR)
            val layout = parseQrLayout(qrData) ?: calculateFallbackLayout(totalQuestions)
            debugInfo["layoutTemplate"] = layout.templateId
            debugInfo["layoutFromQr"] = (layout.templateId != "LEGACY")
            Log.d(TAG, "Using layout: template=${layout.templateId}, cols=${layout.columns}, rows=${layout.rows}")
            
            // Step 8: Auto-calibrate fill threshold using calibration marks in footer
            val calibration = calibrateFillThreshold(warpedMat, debugInfo)
            val fillThreshold = if (calibration.isCalibrated) calibration.fillThreshold else DEFAULT_FILL_THRESHOLD
            debugInfo["fillThreshold"] = fillThreshold
            debugInfo["calibrationSuccess"] = calibration.isCalibrated
            
            // Step 9: Apply adaptive threshold for bubble detection
            thresholdMat = Mat()
            val blockSize = if (quality == ProcessingQuality.FAST) 11 else 15
            Imgproc.adaptiveThreshold(
                warpedMat, thresholdMat,
                255.0,
                Imgproc.ADAPTIVE_THRESH_GAUSSIAN_C,
                Imgproc.THRESH_BINARY_INV,
                blockSize, 4.0
            )
            
            // Step 9.5: Validate template using row marks (v2 sheets only)
            if (layout.templateId != "LEGACY") {
                val rowMarkValidation = validateRowMarks(warpedMat, layout, debugInfo)
                debugInfo["rowMarkValidation"] = rowMarkValidation
                if (rowMarkValidation < 0.6) {
                    Log.w(TAG, "Low row mark validation score: $rowMarkValidation - template mismatch possible")
                    debugInfo["templateMismatchWarning"] = true
                }
            }
            
            // Step 10: Detect OMR ID with validation
            val omrIdResult = detectOmrIdWithValidation(thresholdMat, warpedMat, fillThreshold, debugInfo)
            if (omrIdResult == null) {
                return errorResult("Could not read OMR ID. Ensure all 4 digits are clearly filled.", debugInfo)
            }
            debugInfo["omrId"] = omrIdResult.first
            debugInfo["omrIdConfidence"] = omrIdResult.second
            
            // Step 11: Detect answers using layout from QR (v2) or fallback calculation (v1)
            val answersResult = detectAnswersWithLayout(thresholdMat, warpedMat, totalQuestions, layout, fillThreshold, debugInfo)
            debugInfo["answersDetected"] = answersResult.first.size
            debugInfo["answersConfidence"] = answersResult.second
            
            // Step 12: Calculate overall confidence
            val confidence = calculateOverallConfidence(
                timingMarkScore = timingMarkScore,
                calibrationSuccess = calibration.isCalibrated,
                omrIdConfidence = omrIdResult.second,
                answersConfidence = answersResult.second,
                qrDetected = qrData != null,
                debugInfo = debugInfo
            )
            
            val processingTimeMs = System.currentTimeMillis() - startTime
            debugInfo["processingTimeMs"] = processingTimeMs
            Log.d(TAG, "Processing completed in ${processingTimeMs}ms")
            
            return ProcessingResult(
                success = true,
                omrId = omrIdResult.first,
                answers = answersResult.first,
                confidence = confidence,
                qrData = qrData,
                errorMessage = null,
                debugInfo = debugInfo
            )
            
        } catch (e: OutOfMemoryError) {
            Log.e(TAG, "Out of memory during processing", e)
            System.gc()  // Try to recover
            return errorResult("Device ran out of memory. Please close other apps and try again.", debugInfo)
        } catch (e: Exception) {
            Log.e(TAG, "Processing error: ${e.message}", e)
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
            val hasGoodLighting = imageQuality.brightnessScore in 70.0..220.0 &&
                imageQuality.contrastScore >= 0.2

            val debugInfo = mutableMapOf<String, Any>()
            val corners = detectCornerMarkersAdaptive(
                grayMat,
                determineProcessingQuality(),
                debugInfo
            )

            if (corners == null || !corners.isValid()) {
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
                    hint = buildPreCaptureHint(imageQuality)
                )
            }

            val alignmentScore = calculateSheetAlignmentScore(
                corners,
                grayMat.cols().toDouble(),
                grayMat.rows().toDouble()
            )
            val isAligned = alignmentScore >= 0.65

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

        val maxDim = maxOf(bounds.outWidth, bounds.outHeight)
        var sampleSize = 1
        while (maxDim / sampleSize > maxDimension * 2) {
            sampleSize *= 2
        }

        val decodeOptions = BitmapFactory.Options().apply {
            inJustDecodeBounds = false
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.RGB_565
        }

        val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size, decodeOptions)
            ?: return null

        return downscaleIfNeeded(bitmap, maxDimension)
    }

    private fun normalizedBrightness(brightnessScore: Double): Double {
        return (brightnessScore / 255.0).coerceIn(0.0, 1.0)
    }

    private fun normalizeSharpness(blurScore: Double): Double {
        // Map the OpenCV Laplacian variance to the 0-1 UI scale used by Flutter.
        return (blurScore / (MIN_BLUR_THRESHOLD * 2.0)).coerceIn(0.0, 1.0)
    }

    private fun buildPreCaptureHint(quality: ImageQuality): String {
        return when {
            quality.brightnessScore < 60 -> "Improve lighting"
            quality.brightnessScore > 230 -> "Reduce glare"
            quality.blurScore < MIN_BLUR_THRESHOLD * 0.6 -> "Hold steady"
            quality.contrastScore < 0.15 -> "Improve sheet contrast"
            else -> "Position sheet in frame"
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
        // 1. Apply CLAHE (Contrast Limited Adaptive Histogram Equalization) for low contrast
        if (quality.contrastScore < 0.4) {
            Log.d(TAG, "Applying CLAHE for contrast enhancement")
            val clahe = Imgproc.createCLAHE(2.0, Size(8.0, 8.0))
            clahe.apply(grayMat, grayMat)
        }
        
        // 2. Adjust brightness if too dark or too bright
        if (quality.brightnessScore < 80) {
            // Image is dark - brighten it
            val alpha = 1.2  // Contrast multiplier
            val beta = 40.0   // Brightness addition
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
     * Build a helpful error message based on image quality issues
     */
    private fun buildCornerDetectionErrorMessage(quality: ImageQuality): String {
        return when {
            quality.blurScore < MIN_BLUR_THRESHOLD * 0.3 -> 
                "Image is too blurry. Hold your phone steady and tap to focus before capturing."
            quality.brightnessScore < 50 ->
                "Image is too dark. Move to a brighter area or turn on a light."
            quality.brightnessScore > 230 ->
                "Image is overexposed. Reduce lighting or avoid direct light on the sheet."
            quality.contrastScore < 0.15 ->
                "Cannot distinguish the sheet. Ensure the paper is flat with even lighting."
            quality.noiseScore > NOISE_THRESHOLD * 2 ->
                "Image is very noisy. Clean your camera lens and ensure good lighting."
            else ->
                "Could not detect all 4 corner markers. Ensure the entire sheet is visible with good lighting."
        }
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
        
        // If primary method failed, try multi-threshold approach (good for low-quality cameras)
        if (corners == null || !corners.isValid()) {
            Log.d(TAG, "Primary corner detection failed, trying multi-threshold approach")
            debugInfo["usingMultiThreshold"] = true
            corners = detectCornersMultiThreshold(grayMat, width, height, debugInfo)
        }
        
        // Last resort: edge-based detection
        if (corners == null || !corners.isValid()) {
            Log.d(TAG, "Multi-threshold failed, trying edge-based detection")
            debugInfo["usingEdgeDetection"] = true
            corners = detectCornersEdgeBased(grayMat, width, height, debugInfo)
        }
        
        return corners
    }
    
    /**
     * Multi-threshold corner detection - tries multiple threshold values
     * Especially useful for low-contrast/poor lighting conditions
     */
    private fun detectCornersMultiThreshold(grayMat: Mat, width: Double, height: Double,
                                             debugInfo: MutableMap<String, Any>): DetectedCorners? {
        // Try multiple fixed threshold values
        val thresholds = listOf(80.0, 100.0, 120.0, 140.0, 160.0)
        
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
        
        // Use simple Gaussian blur instead of expensive bilateral filter
        val blurredMat = Mat()
        Imgproc.GaussianBlur(grayMat, blurredMat, Size(5.0, 5.0), 0.0)
        
        // Apply Otsu threshold
        val binaryMat = Mat()
        Imgproc.threshold(blurredMat, binaryMat, 0.0, 255.0, Imgproc.THRESH_BINARY_INV + Imgproc.THRESH_OTSU)
        
        // Find contours (RETR_EXTERNAL is faster than RETR_TREE)
        val contours = mutableListOf<MatOfPoint>()
        val hierarchy = Mat()
        Imgproc.findContours(binaryMat, contours, hierarchy, Imgproc.RETR_EXTERNAL, Imgproc.CHAIN_APPROX_SIMPLE)
        
        val markerCandidates = mutableListOf<Point>()
        
        for (contour in contours) {
            val area = Imgproc.contourArea(contour)
            
            // Filter by expected marker area
            val expectedArea = (width * CORNER_MARKER_SIZE / OUTPUT_WIDTH) * (height * CORNER_MARKER_SIZE / OUTPUT_HEIGHT)
            if (area < expectedArea * 0.3 || area > expectedArea * 4) continue
            
            // Check aspect ratio
            val rect = Imgproc.boundingRect(contour)
            val aspectRatio = rect.width.toDouble() / rect.height.toDouble()
            if (aspectRatio < 0.7 || aspectRatio > 1.4) continue
            
            // Add center as candidate
            markerCandidates.add(Point(
                rect.x + rect.width / 2.0,
                rect.y + rect.height / 2.0
            ))
        }
        
        blurredMat.release()
        binaryMat.release()
        hierarchy.release()
        
        debugInfo["balancedCandidates"] = markerCandidates.size
        
        if (markerCandidates.size < 4) {
            return null
        }
        
        return assignCornersFromCandidates(markerCandidates, width, height, debugInfo)
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
        // Apply threshold
        val binary = Mat()
        Imgproc.threshold(roi, binary, 0.0, 255.0, Imgproc.THRESH_BINARY_INV + Imgproc.THRESH_OTSU)
        
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
        // Find the candidate closest to each corner
        val topLeft = candidates.filter { it.x < width * 0.3 && it.y < height * 0.3 }
            .minByOrNull { it.x + it.y }
        val topRight = candidates.filter { it.x > width * 0.7 && it.y < height * 0.3 }
            .minByOrNull { (width - it.x) + it.y }
        val bottomLeft = candidates.filter { it.x < width * 0.3 && it.y > height * 0.7 }
            .minByOrNull { it.x + (height - it.y) }
        val bottomRight = candidates.filter { it.x > width * 0.7 && it.y > height * 0.7 }
            .minByOrNull { (width - it.x) + (height - it.y) }
        
        if (topLeft == null || topRight == null || bottomLeft == null || bottomRight == null) {
            debugInfo["cornerAssignmentFailed"] = true
            return null
        }
        
        return DetectedCorners(topLeft, topRight, bottomLeft, bottomRight)
    }
    
    /**
     * Apply perspective transform to get a properly aligned image
     */
    private fun applyPerspectiveTransform(srcMat: Mat, corners: DetectedCorners): Mat {
        val srcPoints = MatOfPoint2f(
            corners.topLeft,
            corners.topRight,
            corners.bottomRight,
            corners.bottomLeft
        )
        
        val dstPoints = MatOfPoint2f(
            Point(0.0, 0.0),
            Point(OUTPUT_WIDTH.toDouble(), 0.0),
            Point(OUTPUT_WIDTH.toDouble(), OUTPUT_HEIGHT.toDouble()),
            Point(0.0, OUTPUT_HEIGHT.toDouble())
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
        
        val binary = Mat()
        Imgproc.threshold(warpedMat, binary, 0.0, 255.0, Imgproc.THRESH_BINARY_INV + Imgproc.THRESH_OTSU)
        
        // Check top edge timing marks
        var x = 60.0
        while (x < 535) {
            expectedMarks++
            if (checkTimingMark(binary, x, TIMING_MARK_EDGE_OFFSET)) {
                foundMarks++
            }
            x += TIMING_MARK_SPACING
        }
        
        // Check bottom edge timing marks
        x = 60.0
        while (x < 535) {
            expectedMarks++
            if (checkTimingMark(binary, x, OUTPUT_HEIGHT - TIMING_MARK_EDGE_OFFSET)) {
                foundMarks++
            }
            x += TIMING_MARK_SPACING
        }
        
        // Check left edge timing marks
        var y = 60.0
        while (y < 780) {
            expectedMarks++
            if (checkTimingMark(binary, TIMING_MARK_EDGE_OFFSET, y)) {
                foundMarks++
            }
            y += TIMING_MARK_SPACING
        }
        
        // Check right edge timing marks
        y = 60.0
        while (y < 780) {
            expectedMarks++
            if (checkTimingMark(binary, OUTPUT_WIDTH - TIMING_MARK_EDGE_OFFSET, y)) {
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
    private fun checkTimingMark(binary: Mat, x: Double, y: Double): Boolean {
        val radius = (TIMING_MARK_SIZE / 2 + 2).toInt()
        val cx = x.toInt().coerceIn(radius, binary.cols() - radius - 1)
        val cy = y.toInt().coerceIn(radius, binary.rows() - radius - 1)
        
        val roi = Mat(binary, Rect(cx - radius, cy - radius, radius * 2, radius * 2))
        val whitePixels = Core.countNonZero(roi)
        val totalPixels = roi.rows() * roi.cols()
        roi.release()
        
        // Timing mark should have significant fill
        return whitePixels.toDouble() / totalPixels > 0.15
    }
    
    /**
     * Detect and decode QR code from the header area
     */
    private fun detectQRCode(warpedMat: Mat, debugInfo: MutableMap<String, Any>): String? {
        try {
            // QR code is in the top-right area of the header
            val qrRegion = Rect(
                (OUTPUT_WIDTH * 0.7).toInt(),
                MARGIN_TOP.toInt(),
                (OUTPUT_WIDTH * 0.25).toInt(),
                100
            )
            
            // Ensure region is within bounds
            val safeRegion = Rect(
                qrRegion.x.coerceIn(0, warpedMat.cols() - 1),
                qrRegion.y.coerceIn(0, warpedMat.rows() - 1),
                qrRegion.width.coerceAtMost(warpedMat.cols() - qrRegion.x),
                qrRegion.height.coerceAtMost(warpedMat.rows() - qrRegion.y)
            )
            
            val qrRoi = Mat(warpedMat, safeRegion)
            val qrData = qrDetector.detectAndDecode(qrRoi)
            qrRoi.release()
            
            if (qrData.isNotEmpty()) {
                Log.d(TAG, "QR Code detected: $qrData")
                return qrData
            }
            
            // Try full image if region detection failed
            val fullQrData = qrDetector.detectAndDecode(warpedMat)
            if (fullQrData.isNotEmpty()) {
                Log.d(TAG, "QR Code detected (full scan): $fullQrData")
                return fullQrData
            }
            
        } catch (e: Exception) {
            Log.w(TAG, "QR detection error: ${e.message}")
            debugInfo["qrError"] = e.message ?: "Unknown"
        }
        
        return null
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
            
            val layoutJson = json.optJSONObject("layout") ?: return null
            
            return QrLayoutMetadata(
                templateId = layoutJson.optString("template", ""),
                columns = layoutJson.optInt("cols", 0),
                rows = layoutJson.optInt("rows", 0),
                gridTop = layoutJson.optDouble("gridTop", ANSWER_GRID_TOP),
                gridBottom = layoutJson.optDouble("gridBottom", ANSWER_GRID_BOTTOM),
                rowHeight = layoutJson.optDouble("rowHeight", 0.0),
                columnWidth = layoutJson.optDouble("colWidth", 0.0),
                bubbleSpacingX = layoutJson.optDouble("bubbleSpacingX", 0.0)
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
            val filledFill = sampleBubbleFill(warpedMat, CALIBRATION_FILLED_X, CALIBRATION_Y)
            val emptyFill = sampleBubbleFill(warpedMat, CALIBRATION_EMPTY_X, CALIBRATION_Y)
            
            debugInfo["calibrationFilledSample"] = filledFill
            debugInfo["calibrationEmptySample"] = emptyFill
            debugInfo["calibrationFilledX"] = CALIBRATION_FILLED_X
            debugInfo["calibrationEmptyX"] = CALIBRATION_EMPTY_X
            debugInfo["calibrationY"] = CALIBRATION_Y
            
            // If we got good samples, calculate threshold
            if (filledFill > emptyFill + 0.15) {
                val threshold = (filledFill + emptyFill) / 2
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
    private fun sampleBubbleFill(grayMat: Mat, centerX: Double, centerY: Double): Double {
        val radius = (BUBBLE_DIAMETER / 2 + 2).toInt()
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
                                           debugInfo: MutableMap<String, Any>): Pair<String, Double>? {
        // Use fixed OMR ID positions from OmrPageConstants
        debugInfo["omrIdFirstColumnX"] = OMR_ID_FIRST_COLUMN_X
        debugInfo["omrIdFirstRowY"] = OMR_ID_FIRST_ROW_Y
        debugInfo["omrIdColumnSpacing"] = OMR_ID_COLUMN_SPACING
        debugInfo["omrIdRowSpacing"] = OMR_ID_ROW_SPACING
        
        val digits = StringBuilder()
        val confidences = mutableListOf<Double>()
        
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
                val result = analyzeBubblePrecise(thresholdMat, grayMat, columnX, bubbleY)
                
                if (result.fillPercentage > bestFill) {
                    secondBestFill = bestFill
                    bestFill = result.fillPercentage
                    bestDigit = digit
                } else if (result.fillPercentage > secondBestFill) {
                    secondBestFill = result.fillPercentage
                }
            }
            
            // Validate: best should be significantly higher than second best
            if (bestDigit >= 0 && bestFill > fillThreshold) {
                val separation = bestFill - secondBestFill
                val confidence = minOf(separation / 0.2, 1.0)  // Good if >0.2 separation
                
                digits.append(bestDigit)
                confidences.add(confidence)
            } else {
                debugInfo["omrIdColumn${col}Failed"] = mapOf(
                    "bestFill" to bestFill,
                    "threshold" to fillThreshold
                )
                return null
            }
        }
        
        val avgConfidence = confidences.average()
        debugInfo["omrIdDigitConfidences"] = confidences
        
        return Pair(digits.toString().padStart(4, '0'), avgConfidence)
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
                val result = analyzeBubblePrecise(thresholdMat, grayMat, bubbleX, rowCenterY)
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
                val result = analyzeBubblePrecise(thresholdMat, grayMat, bubbleX, rowCenterY)
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
        
        debugInfo["multipleSelectionsLayout"] = multipleSelections
        debugInfo["noSelectionsLayout"] = noSelections
        debugInfo["ambiguousQuestions"] = ambiguousQuestions.toList()
        
        val avgConfidence = if (confidences.isNotEmpty()) confidences.average() else 0.0
        return Pair(answers, avgConfidence)
    }
    
    /**
     * Precise bubble analysis with multiple sampling methods
     */
    private fun analyzeBubblePrecise(thresholdMat: Mat, grayMat: Mat, 
                                      centerX: Double, centerY: Double): BubbleResult {
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
        Imgproc.circle(mask, Point(size / 2.0, size / 2.0), (size * 0.35).toInt(), Scalar(255.0), -1)
        
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
        val combinedFill = (thresholdFill + intensityFill) / 2
        
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
            filled = combinedFill > DEFAULT_FILL_THRESHOLD,
            fillPercentage = combinedFill,
            confidence = confidence,
            centerX = centerX,
            centerY = centerY
        )
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

