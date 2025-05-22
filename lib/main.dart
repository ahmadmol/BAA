import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:image/image.dart' as imglib;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(Main(cameras: cameras));
}

class Main extends StatelessWidget {
  final List<CameraDescription> cameras;

  const Main({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CameraStreamPage(cameras: cameras),
    );
  }
}

class CameraStreamPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraStreamPage({super.key, required this.cameras});

  @override
  _CameraStreamPageState createState() => _CameraStreamPageState();
}

class _CameraStreamPageState extends State<CameraStreamPage> {
  late CameraController _controller;
  CameraImage? _latestImage;
  Timer? _timer;
  String _resultText = '';

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.cameras[0],
      ResolutionPreset.medium,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _startStreaming();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startStreaming() {
    _controller.startImageStream((CameraImage image) {
      _latestImage = image;
    });

    _timer = Timer.periodic(const Duration(milliseconds: 1000), (timer) async {
      if (_latestImage == null) return;

      try {
        final imglib.Image rawImage = Converter.convertCameraImage(_latestImage!);
        final imglib.Image resizedImage = imglib.copyResize(rawImage, width: 300);

        final Uint8List jpgBytes = Uint8List.fromList(
          imglib.encodeJpg(resizedImage, quality: 50),
        );

        await sendImageData(jpgBytes);

      } catch (e) {
        print("Error processing/sending image: $e");
      }

      _latestImage = null;
    });
  }

  Future<void> sendImageData(Uint8List data) async {
    Socket? socket;
    try {
      socket = await Socket.connect('192.168.171.38', 50001);
      print("✅ Connected! Sending length...");
      socket.add(utf8.encode('${data.length}\n'));
      socket.add(data);
      await socket.flush();

      final response = await socket
          .transform(utf8.decoder as StreamTransformer<Uint8List, dynamic>)
          .transform(const LineSplitter())
          .first;

      if (mounted) {
        setState(() {
          _resultText = response;
        });
      }
    } catch (e) {
      print('Socket connection error: $e');
    } finally {
      await socket?.close();
    }
    print("📤 Sending image of size: ${data.length} bytes");

  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Align(
          alignment: Alignment.centerRight,
          child: const Text(
            "مساعد ذكي للمكفوفين",
            style: TextStyle(color: Colors.white),
          ),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(child: CameraPreview(_controller)),
          Container(
            width: double.infinity,
            height: 400,
            color: Colors.black,
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Text(
                _resultText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Converter {
  static imglib.Image convertCameraImage(CameraImage cameraImage) {
    if (cameraImage.format.group == ImageFormatGroup.yuv420) {
      return convertYUV420ToImage(cameraImage);
    } else if (cameraImage.format.group == ImageFormatGroup.bgra8888) {
      return convertBGRA8888ToImage(cameraImage);
    } else {
      throw Exception('Unsupported image format: ${cameraImage.format.group}');
    }
  }

  static imglib.Image convertBGRA8888ToImage(CameraImage cameraImage) {
    return imglib.Image.fromBytes(
      width: cameraImage.planes[0].width!,
      height: cameraImage.planes[0].height!,
      bytes: cameraImage.planes[0].bytes.buffer,
      order: imglib.ChannelOrder.bgra,
    );
  }

  static imglib.Image convertYUV420ToImage(CameraImage cameraImage) {
    final int width = cameraImage.width;
    final int height = cameraImage.height;

    final imglib.Image img = imglib.Image(width: width, height: height);
    final Uint8List yPlane = cameraImage.planes[0].bytes;
    final Uint8List uPlane = cameraImage.planes[1].bytes;
    final Uint8List vPlane = cameraImage.planes[2].bytes;

    final int yRowStride = cameraImage.planes[0].bytesPerRow;
    final int yPixelStride = cameraImage.planes[0].bytesPerPixel!;

    final int uvRowStride = cameraImage.planes[1].bytesPerRow;
    final int uvPixelStride = cameraImage.planes[1].bytesPerPixel!;

    for (int h = 0; h < height; h++) {
      final int uvRow = h >> 1;
      for (int w = 0; w < width; w++) {
        final int uvCol = w >> 1;

        final int yIndex = h * yRowStride + w * yPixelStride;
        final int uvIndex = uvRow * uvRowStride + uvCol * uvPixelStride;

        final int y = yPlane[yIndex];
        final int u = uPlane[uvIndex];
        final int v = vPlane[uvIndex];

        int r = (y + (v * 1436 / 1024) - 179).round();
        int g = (y - (u * 46549 / 131072) + 44 - (v * 93604 / 131072) + 91).round();
        int b = (y + (u * 1814 / 1024) - 227).round();

        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);

        img.setPixelRgb(w, h, r, g, b);
      }
    }

    return img;
  }
}
