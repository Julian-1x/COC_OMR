import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'opencv_bridge.dart';

class OpenCVTestPage extends StatefulWidget {
  final CameraController controller;

  const OpenCVTestPage({super.key, required this.controller});

  @override
  State<OpenCVTestPage> createState() => _OpenCVTestPageState();
}

class _OpenCVTestPageState extends State<OpenCVTestPage> {
  Uint8List? processedImage;
  bool processing = false;

  Future<void> runOpenCV() async {
    setState(() => processing = true);

    final file = await widget.controller.takePicture();
    final bytes = await file.readAsBytes();

    final result = await OpenCVBridge.process(bytes);

    setState(() {
      processedImage = result;
      processing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("OpenCV Test")),
      body: Column(
        children: [
          Expanded(
            child: processedImage == null
                ? CameraPreview(widget.controller)
                : Image.memory(processedImage!),
          ),
          ElevatedButton(
            onPressed: processing ? null : runOpenCV,
            child: processing
                ? const CircularProgressIndicator()
                : const Text("Capture + Process"),
          ),
        ],
      ),
    );
  }
}
