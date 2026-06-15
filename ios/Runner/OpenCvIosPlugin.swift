import Flutter
import UIKit

/// Registers MethodChannel `opencv` for iOS (matches Android `MainActivity` channel).
public final class OpenCvIosPlugin: NSObject, FlutterPlugin {
  private static let channelName = "opencv"
  private static let maxBytes = 20 * 1024 * 1024
  private var isBusy = false
  private let queue = DispatchQueue(label: "omr.opencv.process", qos: .userInitiated)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = OpenCvIosPlugin()
    channel.setMethodCallHandler(instance.handle)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ping":
      result(OmrNativeBridge.isOpenCvReady() ? "pong" : "not_ready")
    case "isReady":
      result(OmrNativeBridge.isOpenCvReady())
    case "getDeviceInfo":
      result(OmrNativeBridge.deviceInfo())
    case "process":
      let pdata = (call.arguments as? FlutterStandardTypedData)?.data
        ?? call.arguments as? Data
      guard let data = pdata else {
        result(FlutterError(code: "INVALID_INPUT", message: "No image data", details: nil))
        return
      }
      runExclusive(data: data, totalQuestions: 50, result: result)
    case "processWithConfig":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "INVALID_INPUT", message: "Invalid arguments", details: nil))
        return
      }
      let img = args["image"]
      let bytes = (img as? FlutterStandardTypedData)?.data ?? img as? Data
      guard let data = bytes else {
        result(FlutterError(code: "INVALID_INPUT", message: "No image data", details: nil))
        return
      }
      let total = args["totalQuestions"] as? Int ?? 50
      runExclusive(data: data, totalQuestions: total, result: result)
    case "detectSheet":
      let d = (call.arguments as? FlutterStandardTypedData)?.data ?? call.arguments as? Data
      guard let data = d else {
        result(FlutterError(code: "INVALID_INPUT", message: "No image data", details: nil))
        return
      }
      queue.async {
        let map = OmrNativeBridge.detectSheet(data) ?? [:]
        DispatchQueue.main.async { result(map) }
      }
    case "analyzeImageQuality":
      let d = (call.arguments as? FlutterStandardTypedData)?.data ?? call.arguments as? Data
      guard let data = d else {
        result(FlutterError(code: "INVALID_INPUT", message: "No image data", details: nil))
        return
      }
      queue.async {
        let map = OmrNativeBridge.analyzeImageQuality(data)
        DispatchQueue.main.async { result(map ?? [:]) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func runExclusive(data: Data, totalQuestions: Int, result: @escaping FlutterResult) {
    if data.count > Self.maxBytes {
      result(FlutterError(code: "IMAGE_TOO_LARGE", message: "Image exceeds size limit", details: nil))
      return
    }
    if !OmrNativeBridge.isOpenCvReady() {
      result(FlutterError(code: "OPENCV_NOT_READY", message: "OpenCV not ready", details: nil))
      return
    }
    if isBusy {
      result(FlutterError(code: "BUSY", message: "Already processing an image", details: nil))
      return
    }
    isBusy = true
    queue.async { [weak self] in
      let json = OmrNativeBridge.process(withImageBytes: data, totalQuestions: totalQuestions)
      DispatchQueue.main.async {
        self?.isBusy = false
        if let json {
          result(json)
        } else {
          result(FlutterError(code: "PROCESS_ERROR", message: "Processing failed", details: nil))
        }
      }
    }
  }
}
