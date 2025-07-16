// services/camera_service.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';
import 'package:image/image.dart' as imglib;

class CameraService {
  final List<CameraDescription> cameras;
  late CameraController controller;
  CameraImage? latestImage;
  int currentCameraIndex = 0;

  CameraService(this.cameras);

  Future<void> initializeCamera() async {
    controller = CameraController(
      cameras[currentCameraIndex],
      ResolutionPreset.max,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await controller.initialize();
    await controller.setExposureMode(ExposureMode.auto);
    await controller.setFocusMode(FocusMode.auto);
  }

  Future<void> switchCamera() async {
    await controller.stopImageStream();
    await controller.dispose();
    currentCameraIndex = (currentCameraIndex + 1) % cameras.length;
    await initializeCamera();
  }

  void startImageStream(Function(CameraImage) onImageAvailable) {
    controller.startImageStream((CameraImage image) {
      latestImage = image;
      onImageAvailable(image);
    });
  }

  Future<Map<String, dynamic>?> sendImageToServer(Uint8List data) async {
    try {
      final uri = Uri.parse('http://192.168.1.102:5050/upload');
      final request = http.MultipartRequest('POST', uri)
        ..files.add(http.MultipartFile.fromBytes(
          'image',
          data,
          filename: 'image.jpg',
          contentType: MediaType('image', 'jpeg'),
        ));

      final response = await request.send();
      if (response.statusCode == 200) {
        final responseBody = await response.stream.bytesToString();
        final jsonResponse = jsonDecode(responseBody);
        return {
          'success': true,
          'objects': jsonResponse['objects'],
          'processed_image': base64Decode(jsonResponse['processed_image']),
        };
      }
    } catch (e) {
      print("Server error: $e");
    }
    return null;
  }

  void dispose() {
    controller.dispose();
  }

  static imglib.Image convertCameraImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final imglib.Image img = imglib.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int uvIndex = ((y ~/ 2) * uPlane.bytesPerRow) + ((x ~/ 2) * uPlane.bytesPerPixel!);
        final int yIndex = y * yPlane.bytesPerRow + x * yPlane.bytesPerPixel!;
        final int Y = yPlane.bytes[yIndex];
        final int U = uPlane.bytes[uvIndex] - 128;
        final int V = vPlane.bytes[uvIndex] - 128;
        final int R = (Y + 1.370705 * V).clamp(0, 255).toInt();
        final int G = (Y - 0.337633 * U - 0.698001 * V).clamp(0, 255).toInt();
        final int B = (Y + 1.732446 * U).clamp(0, 255).toInt();
        img.setPixelRgb(x, y, R, G, B);
      }
    }
    return img;
  }
}
