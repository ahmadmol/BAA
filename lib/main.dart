import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:image/image.dart' as imglib;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

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
  List<String> _detectedObjects = [];
  late Directory _resultsDirectory;
  IconData _getIcon(String label) {
    final icons = {
      'person': Icons.person,
      'car': Icons.directions_car,
      'dog': Icons.pets,
      'cat': Icons.pets,
      'chair': Icons.chair,
      'tv': Icons.tv,
    };
    return icons[label.toLowerCase()] ?? Icons.help_outline;
  }
  Future<void> saveToGallery(Uint8List bytes, int count) async {
    final String folderPath = "/storage/emulated/0/DCIM/DetectedImages";
    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final File file = File('$folderPath/image_$count.jpg');
    await file.writeAsBytes(bytes);
    print("✅ تم حفظ الصورة في معرض الصور: ${file.path}");
  }

  @override
  void initState() {
    super.initState();
    _initializeAsyncTasks(); // دالة جديدة تقوم بالمهام غير المتزامنة
  }

  Future<void> _initializeAsyncTasks() async {
    await _initCamera();
    await Permission.storage.request();
  }


  Future<void> _initCamera() async {
    _controller = CameraController(
      widget.cameras[0],
      ResolutionPreset.max, // استخدام أعلى دقة
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _controller.initialize();

    if (!mounted) return;

    setState(() {});

    // إنشاء مجلد results في الذاكرة الداخلية
    final Directory appDir = await getApplicationDocumentsDirectory();
    _resultsDirectory = Directory('${appDir.path}/results');

    if (!await _resultsDirectory.exists()) {
      await _resultsDirectory.create(recursive: true);
      print("✅ تم إنشاء مجلد النتائج: ${_resultsDirectory.path}");
    }

    _startStreaming();
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

    _timer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (_latestImage == null) return;

      // إيقاف تدفق الصور مؤقتاً
      await _controller.stopImageStream();

      try {
        final imglib.Image rawImage = Converter.convertCameraImage(_latestImage!);
        final imglib.Image resizedImage = imglib.copyResize(rawImage, width: 640);

        final imglib.Image adjustedImage = imglib.adjustColor(
          resizedImage,
          saturation: 1.2,
          gamma: 1.0,
        );

        final Uint8List jpgBytes = Uint8List.fromList(
          imglib.encodeJpg(adjustedImage, quality: 85),
        );

        // حفظ الصورة في المجلد داخل الذاكرة الداخلية
        await saveImageToInternalStorage(jpgBytes, timer.tick);

        await sendImageData(jpgBytes);
      } catch (e) {
        print("Error processing/sending image: $e");
      }

      _latestImage = null;

      // إعادة تشغيل تدفق الصور بعد الانتهاء
      await _controller.startImageStream((CameraImage image) {
        _latestImage = image;
      });
    });
  }

  Future<void> saveImageToInternalStorage(Uint8List bytes, int count) async {
    try {
      final file = File('${_resultsDirectory.path}/image_$count.jpg');
      await file.writeAsBytes(bytes);
      print("✅ تم حفظ الصورة في: ${file.path}");
    } catch (e) {
      print("خطأ في حفظ الصورة: $e");
    }
    await saveToGallery(bytes, count);
  }

  Future<void> sendImageData(Uint8List data) async {
    try {
      final uri = Uri.parse('http://192.168.1.105:50002/upload');
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
        if (mounted) {
          setState(() {
            _detectedObjects = responseBody.split(', ').where((e) => e.isNotEmpty).toList();
          });
        }
      } else {
        print('HTTP Error: ${response.statusCode}');
      }
    } catch (e) {
      print('HTTP connection error: $e');
    }

    print("📤 Sent image of size: ${data.length} bytes via HTTP");
  }

  Widget _buildObjectItem(String label) {
    final Map<String, IconData> icons = {
      'person': Icons.person,
      'car': Icons.directions_car,
      'dog': Icons.pets,
      'cat': Icons.pets,
      'chair': Icons.chair,
      'tv': Icons.tv,
    };
    final icon = icons[label.toLowerCase()] ?? Icons.help;

    return Card(
      color: Colors.grey[900],
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: Colors.white, size: 32),
        title: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 20),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Align(
          alignment: Alignment.centerRight,
          child: Text("مساعد ذكي للمكفوفين", style: TextStyle(color: Colors.white)),
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
            child: _detectedObjects.isEmpty
                ? const Center(
              child: Text(
                "لا يوجد كائنات معروفة",
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            )
                : ListView.builder(
              itemCount: _detectedObjects.length,
              itemBuilder: (context, index) {
                final label = _detectedObjects[index];
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[850],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: ListTile(
                    leading: Icon(_getIcon(label), color: Colors.white, size: 32),
                    title: Text(
                      label,
                      style: const TextStyle(color: Colors.white, fontSize: 20),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white38),
                  ),
                );
              },
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

    final yPlane = cameraImage.planes[0];
    final uPlane = cameraImage.planes[1];
    final vPlane = cameraImage.planes[2];

    final imglib.Image image = imglib.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int uvIndex = ((y >> 1) * uPlane.bytesPerRow) + ((x >> 1) * uPlane.bytesPerPixel!);
        final int yIndex = y * yPlane.bytesPerRow + x * yPlane.bytesPerPixel!;

        final int Y = yPlane.bytes[yIndex];
        final int U = uPlane.bytes[uvIndex];
        final int V = vPlane.bytes[uvIndex];

        final int R = (Y + 1.402 * (V - 128)).round().clamp(0, 255);
        final int G = (Y - 0.344136 * (U - 128) - 0.714136 * (V - 128)).round().clamp(0, 255);
        final int B = (Y + 1.772 * (U - 128)).round().clamp(0, 255);

        image.setPixelRgb(x, y, R, G, B);
      }
    }

    return image;
  }
}
