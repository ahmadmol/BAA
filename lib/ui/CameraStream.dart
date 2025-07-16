// ui/camera_stream_page.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as imglib;
import '../services/CameraServices.dart';
import '../services/ProcessingService.dart';
import 'package:camera/camera.dart';


class CameraStreamPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  const CameraStreamPage({super.key, required this.cameras});

  @override
  State<CameraStreamPage> createState() => _CameraStreamPageState();
}

class _CameraStreamPageState extends State<CameraStreamPage> {
  late CameraService cameraService;
  late ProcessingService processingService;
  Timer? _timer;
  bool isProcessing = false;

  @override
  void initState() {
    super.initState();
    cameraService = CameraService(widget.cameras);
    processingService = ProcessingService();
    initialize();
  }

  Future<void> initialize() async {
    await cameraService.initializeCamera();
    await processingService.initialize();
    cameraService.startImageStream((image) {});
    startTimer();
    setState(() {});
  }

  void startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (cameraService.latestImage == null || isProcessing) return;
      isProcessing = true;

      try {
        imglib.Image image =
        CameraService.convertCameraImage(cameraService.latestImage!);
        final resized = imglib.copyResize(image, width: 1280, height: 720);
        final jpg = Uint8List.fromList(imglib.encodeJpg(resized, quality: 90));

        final response = await cameraService.sendImageToServer(jpg);
        if (response != null && response['success']) {
          await processingService.speak(response['objects']);
          await processingService.saveImage(response['processed_image']);
        }
      } catch (e) {
        print("Error: $e");
      } finally {
        isProcessing = false;
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    cameraService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!cameraService.controller.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: CameraPreview(cameraService.controller),
    );
  }
}
