import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as imglib;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

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
  int _currentCameraIndex = 0;
  bool _isProcessing = false;
  String _serverResponse = '';
  List<Uint8List> _processedImages = [];

  @override
  void initState() {
    super.initState();
    _initCamera();
    _initResultsDirectory();
  }

  Future<void> _initResultsDirectory() async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    _resultsDirectory = Directory('${appDir.path}/results');
    if (!await _resultsDirectory.exists()) {
      await _resultsDirectory.create(recursive: true);
    }
  }

  Future<void> _initCamera() async {
    try {
      _controller = CameraController(
        widget.cameras[_currentCameraIndex],
        ResolutionPreset.medium,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _controller.initialize();
      await _controller.setExposureMode(ExposureMode.auto);
      await _controller.setFocusMode(FocusMode.auto);

      if (!mounted) return;
      setState(() {});

      _startStreaming();
    } catch (e) {
      print("Error initializing camera: $e");
      setState(() {
        _serverResponse = "خطأ في تهيئة الكاميرا: $e";
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_isProcessing) return;

    _timer?.cancel();
    await _controller.stopImageStream();
    await _controller.dispose();

    setState(() {
      _currentCameraIndex = (_currentCameraIndex + 1) % widget.cameras.length;
    });

    await _initCamera();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startStreaming() {
    _controller.startImageStream((CameraImage image) {
      if (!mounted) return;
      setState(() {
        _latestImage = image;
      });
    });

    _timer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_latestImage == null || _isProcessing) return;

      _isProcessing = true;
      setState(() {});

      try {
        final imglib.Image rawImage = Converter.convertCameraImage(_latestImage!);
        final imglib.Image resizedImage = imglib.copyResize(rawImage, width: 640, height: 480);
        final imglib.Image denoisedImage = imglib.gaussianBlur(resizedImage, radius: 1);
        final imglib.Image adjustedImage = imglib.adjustColor(
          denoisedImage,
          saturation: 1.1,
          gamma: 1.1,
        );

        final Uint8List jpgBytes = Uint8List.fromList(
          imglib.encodeJpg(adjustedImage, quality: 90),
        );

        final response = await sendImageData(jpgBytes);
        if (response != null && response['success']) {
          final Uint8List processedImage = response['processed_image'];
          setState(() {
            _processedImages.add(processedImage);
            _detectedObjects = response['objects'].split(', ');
            _serverResponse = "تم التحليل بنجاح";
          });

          await _saveProcessedImage(processedImage);
        }
      } catch (e) {
        print("Error processing/sending image: $e");
        setState(() {
          _serverResponse = "خطأ في معالجة الصورة: $e";
        });
      } finally {
        if (mounted) {
          setState(() {
            _isProcessing = false;
            _latestImage = null;
          });
        }
      }
    });
  }

  Future<void> _saveProcessedImage(Uint8List imageBytes) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${_resultsDirectory.path}/processed_$timestamp.jpg');
      await file.writeAsBytes(imageBytes);
      print("✅ تم حفظ الصورة المحللة: ${file.path}");
    } catch (e) {
      print("خطأ في حفظ الصورة المحللة: $e");
    }
  }

  Future<Map<String, dynamic>?> sendImageData(Uint8List data) async {
    try {
      final uri = Uri.parse('http://192.168.1.8:50002/upload');
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
      } else {
        print('HTTP Error: ${response.statusCode}');
        setState(() {
          _serverResponse = "خطأ في الخادم: ${response.statusCode}";
        });
      }
    } catch (e) {
      print('HTTP connection error: $e');
      setState(() {
        _serverResponse = "خطأ في الاتصال بالخادم: $e";
      });
    }
    return null;
  }

  Widget _buildObjectItem(String label) {
    final Map<String, IconData> icons = {
      'person': Icons.person,
      'car': Icons.directions_car,
      'dog': Icons.pets,
      'cat': Icons.pets,
      'chair': Icons.chair,
      'tv': Icons.tv,
      'book': Icons.book,
      'bottle': Icons.water_drop,
      'cell phone': Icons.phone,
      'laptop': Icons.laptop,
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
        trailing: IconButton(
          icon: const Icon(Icons.copy, color: Colors.white),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: label));
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("تم نسخ النص"))
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(_serverResponse, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Align(
          alignment: Alignment.centerRight,
          child: Text("مساعد ذكي للمكفوفين", style: TextStyle(color: Colors.white)),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.switch_camera),
            onPressed: _switchCamera,
          ),
          IconButton(
            icon: const Icon(Icons.photo_library),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => GalleryPage(images: _processedImages)),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: CameraPreview(_controller)),
          Container(
            width: double.infinity,
            height: 350,
            color: Colors.black,
            padding: const EdgeInsets.all(16),
            child: _isProcessing
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : _detectedObjects.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("لا يوجد كائنات معروفة", style: TextStyle(color: Colors.white, fontSize: 18)),
                  const SizedBox(height: 10),
                  Text(_serverResponse, style: const TextStyle(color: Colors.white54)),
                ],
              ),
            )
                : ListView(
              children: [
                ..._detectedObjects.map((obj) => _buildObjectItem(obj)),
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(_serverResponse, style: const TextStyle(color: Colors.white54)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GalleryPage extends StatelessWidget {
  final List<Uint8List> images;

  const GalleryPage({super.key, required this.images});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("الصور المحفوظة"),
        backgroundColor: Colors.black,
      ),
      body: images.isEmpty
          ? const Center(child: Text("لا توجد صور محفوظة"))
          : GridView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: images.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 4,
          mainAxisSpacing: 4,
        ),
        itemBuilder: (context, index) {
          return Image.memory(images[index], fit: BoxFit.cover);
        },
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
      final int yRow = y * yPlane.bytesPerRow;

      for (int x = 0; x < width; x++) {
        final int uvIndex = ((y ~/ 2) * uPlane.bytesPerRow) + ((x ~/ 2) * uPlane.bytesPerPixel!);
        final int yIndex = yRow + x * yPlane.bytesPerPixel!;

        final int Y = yPlane.bytes[yIndex];
        final int U = uPlane.bytes[uvIndex] - 128;
        final int V = vPlane.bytes[uvIndex] - 128;

        final int R = (Y + 1.370705 * V).clamp(0, 255).toInt();
        final int G = (Y - 0.337633 * U - 0.698001 * V).clamp(0, 255).toInt();
        final int B = (Y + 1.732446 * U).clamp(0, 255).toInt();

        image.setPixelRgb(x, y, R, G, B);
      }
    }

    return image;
  }
}
