package edu.coc.omr



import android.content.Context

import android.util.Log

import android.util.Size

import android.view.Surface

import android.view.ViewGroup

import androidx.camera.core.Camera

import androidx.camera.core.CameraSelector

import androidx.camera.core.FocusMeteringAction

import androidx.camera.core.ImageCapture

import androidx.camera.core.ImageCaptureException

import androidx.camera.core.Preview

import androidx.camera.core.resolutionselector.AspectRatioStrategy

import androidx.camera.core.resolutionselector.ResolutionSelector

import androidx.camera.core.resolutionselector.ResolutionStrategy

import androidx.camera.lifecycle.ProcessCameraProvider

import androidx.camera.view.PreviewView

import androidx.core.content.ContextCompat

import androidx.lifecycle.LifecycleOwner

import io.flutter.plugin.common.MethodChannel

import java.io.File

import java.util.concurrent.ExecutorService

import java.util.concurrent.Executors



class ScannerCameraSession(

    private val context: Context,

    val previewView: PreviewView,

) {

    companion object {

        private const val TAG = "ScannerCamera"

        // 4:3 sensor — portrait preview is 3:4; high-res stream avoids upscale blur in the view.

        private val PREVIEW_SIZE = Size(1920, 1440)

        private val CAPTURE_SIZE = Size(3264, 2448)

    }



    private val cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    private var cameraProvider: ProcessCameraProvider? = null

    private var camera: Camera? = null

    private var imageCapture: ImageCapture? = null

    private var viewWidth: Int = 0

    private var viewHeight: Int = 0

    private var previewAspect: Double = 3.0 / 4.0

    private var isBound = false



    init {

        previewView.layoutParams = ViewGroup.LayoutParams(

            ViewGroup.LayoutParams.MATCH_PARENT,

            ViewGroup.LayoutParams.MATCH_PARENT,

        )

        previewView.implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        previewView.scaleType = PreviewView.ScaleType.FILL_CENTER

    }



    fun bind(

        viewWidth: Int,

        viewHeight: Int,

        onReady: (Double) -> Unit,

        onError: (String) -> Unit,

    ) {

        if (isBound && this.viewWidth == viewWidth && this.viewHeight == viewHeight) {

            onReady(previewAspect)

            return

        }



        this.viewWidth = viewWidth

        this.viewHeight = viewHeight



        val lifecycleOwner = ScannerCameraPlugin.hostActivity as? LifecycleOwner

            ?: context.findLifecycleOwner()



        if (lifecycleOwner == null) {

            Log.e(TAG, "No LifecycleOwner — context=${context.javaClass.name}")

            onError("Activity lifecycle unavailable")

            return

        }



        previewView.post {

            bindWhenReady(lifecycleOwner, onReady, onError)

        }

    }



    private fun bindWhenReady(

        lifecycleOwner: LifecycleOwner,

        onReady: (Double) -> Unit,

        onError: (String) -> Unit,

    ) {

        val providerFuture = ProcessCameraProvider.getInstance(context)

        providerFuture.addListener({

            try {

                val provider = providerFuture.get()

                cameraProvider = provider

                provider.unbindAll()

                isBound = false



                val targetRotation = currentTargetRotation()



                val preview = Preview.Builder()

                    .setTargetRotation(targetRotation)

                    .setResolutionSelector(buildPreviewResolutionSelector())

                    .build()

                    .also { it.surfaceProvider = previewView.surfaceProvider }



                imageCapture = ImageCapture.Builder()

                    .setTargetRotation(targetRotation)

                    .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)

                    .setResolutionSelector(buildCaptureResolutionSelector())

                    .setJpegQuality(98)

                    .build()



                camera = provider.bindToLifecycle(

                    lifecycleOwner,

                    CameraSelector.DEFAULT_BACK_CAMERA,

                    preview,

                    imageCapture,

                )



                camera?.cameraControl?.setZoomRatio(1.0f)

                isBound = true



                previewAspect = computePreviewAspect()

                Log.i(TAG, "Camera bound view=${viewWidth}x$viewHeight previewAspect=$previewAspect")

                focusOnSheetCenter()

                onReady(previewAspect)

            } catch (error: Exception) {

                Log.e(TAG, "Camera bind failed", error)

                isBound = false

                onError(error.message ?: "Camera bind failed")

            }

        }, ContextCompat.getMainExecutor(context))

    }



    private fun currentTargetRotation(): Int {

        return previewView.display?.rotation

            ?: ScannerCameraPlugin.hostActivity?.window?.decorView?.display?.rotation

            ?: Surface.ROTATION_0

    }



    private fun computePreviewAspect(): Double {

        if (viewWidth > 0 && viewHeight > 0) {

            return viewWidth.toDouble() / viewHeight

        }

        return previewAspect

    }



    private fun buildPreviewResolutionSelector(): ResolutionSelector {

        return ResolutionSelector.Builder()

            .setResolutionStrategy(

                ResolutionStrategy(

                    PREVIEW_SIZE,

                    ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER,

                ),

            )

            .setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY)

            .build()

    }



    private fun buildCaptureResolutionSelector(): ResolutionSelector {

        return ResolutionSelector.Builder()

            .setResolutionStrategy(

                ResolutionStrategy(

                    CAPTURE_SIZE,

                    ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER,

                ),

            )

            .setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY)

            .build()

    }



    fun configureForScanning() {

        camera?.cameraControl?.setZoomRatio(1.0f)

        focusOnSheetCenter()

    }



    private fun focusOnSheetCenter() {

        setFocusPoint(0.5f, 0.48f)

    }



    fun setFocusPoint(x: Float, y: Float) {

        if (!isBound) {

            return

        }

        val factory = previewView.meteringPointFactory

        val point = factory.createPoint(x, y)

        val action = FocusMeteringAction.Builder(

            point,

            FocusMeteringAction.FLAG_AF or FocusMeteringAction.FLAG_AE,

        )

            .disableAutoCancel()

            .build()

        camera?.cameraControl?.startFocusAndMetering(action)

    }



    fun capture(result: MethodChannel.Result) {

        val capture = imageCapture

        if (capture == null || !isBound) {

            result.error("NOT_READY", "Image capture not ready", null)

            return

        }



        val outputFile = File(

            context.cacheDir,

            "omr_scan_${System.currentTimeMillis()}.jpg",

        )

        capture.targetRotation = currentTargetRotation()

        focusOnSheetCenter()

        val outputOptions = ImageCapture.OutputFileOptions.Builder(outputFile).build()



        capture.takePicture(

            outputOptions,

            cameraExecutor,

            object : ImageCapture.OnImageSavedCallback {

                override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) {

                    try {

                        val bytes = outputFile.readBytes()

                        outputFile.delete()

                        ContextCompat.getMainExecutor(context).execute {

                            result.success(bytes)

                        }

                    } catch (error: Exception) {

                        ContextCompat.getMainExecutor(context).execute {

                            result.error("CAPTURE_READ_FAILED", error.message, null)

                        }

                    }

                }



                override fun onError(exception: ImageCaptureException) {

                    Log.e(TAG, "Capture failed", exception)

                    ContextCompat.getMainExecutor(context).execute {

                        result.error("CAPTURE_FAILED", exception.message, null)

                    }

                }

            },

        )

    }



    fun release() {

        isBound = false

        try {

            cameraProvider?.unbindAll()

        } catch (error: Exception) {

            Log.w(TAG, "Release unbind failed: ${error.message}")

        }

        camera = null

        imageCapture = null

        cameraProvider = null

        if (!cameraExecutor.isShutdown) {

            cameraExecutor.shutdown()

        }

    }

}


